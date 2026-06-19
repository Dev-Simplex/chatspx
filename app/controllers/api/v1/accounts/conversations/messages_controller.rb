class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController # rubocop:disable Metrics/ClassLength
  before_action :ensure_api_inbox, only: :update, unless: :content_update?

  WAHA_ECHO_MARKER_API = 'Enviado via API'.freeze
  WAHA_ECHO_MARKER_EDITED = 'Editado no WhatsApp'.freeze
  # Echo markers para special messages que o app WAHA externo replica como
  # mensagem de texto formatada (location, contact, etc). Quando o conteúdo bate
  # com WAHA_ECHO_MARKER_API + qualquer um destes, a criação é suprimida — o
  # painel já tem a Message original (com attachment) criada pela própria UI.
  WAHA_ECHO_MARKER_LOCATION = 'Localização compartilhada'.freeze
  WAHA_ECHO_MARKER_CONTACT = 'Contato compartilhado'.freeze
  WAHA_ECHO_MARKERS_SPECIAL = [
    WAHA_ECHO_MARKER_EDITED,
    WAHA_ECHO_MARKER_LOCATION,
    WAHA_ECHO_MARKER_CONTACT
  ].freeze
  WAHA_ERROR_MARKER = 'Não foi possível receber uma mensagem do WhatsApp'.freeze
  WAHA_ERROR_EVENT = 'message.edited'.freeze

  # Markers de mensagens-erro técnicas postadas pelo app WAHA externo
  # (chatwoot-waha-app, Node.js fora do nosso repo) quando ele tem erro
  # interno (retry/timeout/timestamp NaN) e cospe o stacktrace via API do
  # Chatwoot. Suprimidos para não poluir o painel do agente.
  WAHA_ERROR_MARKERS = [
    '⚠️ Não foi possível',
    '❌ Não há mais tentativas',
    'ChatWoot API Error',
    'API Error: Request failed',
    'error: insert into',
    '0NaN-NaN-NaN',
    'Invalid URL',
    'ERR_INVALID_URL',
    'app_chatwoot_chatwoot_messages',
    'Tentativa: 3 / 3'
  ].freeze

  def index
    @include_meta = include_meta?
    @messages = message_finder.perform
    @has_more = message_finder.has_more
    enqueue_waha_status_sync
  end

  def create
    return render json: { status: 'suppressed' }, status: :ok if waha_echo?
    return render json: { status: 'suppressed' }, status: :ok if waha_edit_error_notification?
    return render json: { status: 'suppressed', reason: 'waha_error_message' }, status: :ok if waha_error_message?(params[:content])
    return render_whatsapp_invalid_error if whatsapp_number_invalid_for_outgoing?

    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_could_not_create_error(e.message)
  end

  def update
    if content_update?
      Messages::UpdateContentService.new(message, permitted_params[:content]).perform
    else
      Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    end
    @message = message
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
    render_could_not_create_error(e.message)
  rescue Rack::Timeout::RequestTimeoutException
    # Synchronous WAHA lookup blew the 15s rack-timeout budget. Surface a friendly
    # toast instead of a generic 500. The eager source_id backfill (SendReplyJob)
    # should make this rescue rarely trigger.
    render_could_not_create_error(I18n.t('errors.messages.update.timeout'))
  end

  def destroy
    if message.content_type.in?(%w[input_nps input_csat])
      return render json: { error: I18n.t('conversations.messages.undeletable') }, status: :unprocessable_entity
    end

    Messages::DeleteContentService.new(message).perform
    @message = message
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_could_not_create_error(e.message)
  rescue Rack::Timeout::RequestTimeoutException
    # Synchronous WAHA delete-for-everyone (and its message lookup) blew the 15s
    # rack-timeout budget. Surface a friendly toast instead of a generic 500.
    render_could_not_create_error(I18n.t('errors.messages.update.timeout'))
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_could_not_create_error(e.message)
  end

  def translate
    translated_content = Messages::TranslateService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    return head :ok if translated_content.nil?

    render json: { content: translated_content }
  end

  def star
    message.update!(starred: !message.starred?)
    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_UPDATED,
      Time.zone.now,
      message: message,
      performed_by: Current.user
    )
    render json: { starred: message.starred }
  end

  def share_location # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    latitude = location_params[:latitude].to_f
    longitude = location_params[:longitude].to_f
    address = location_params[:address].to_s.presence

    return render_could_not_create_error('Coordinates are required') if latitude.zero? && longitude.zero?

    user = Current.user || @resource

    # content fica vazio: o LocationBubble nativo (frontend) renderiza só o
    # mapa + endereço como subtítulo via attachment.fallback_title. O
    # additional_attributes['location']['address'] é redundância pra
    # resiliência futura (ex: render fora do attachment).
    location_extras = address ? { 'location' => { 'address' => address } } : {}

    @message = ActiveRecord::Base.transaction do
      msg = @conversation.messages.create!(
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        message_type: :outgoing,
        content: '',
        additional_attributes: location_extras,
        sender: user
      )

      msg.attachments.create!(
        account_id: @conversation.account_id,
        file_type: :location,
        coordinates_lat: latitude,
        coordinates_long: longitude,
        fallback_title: address
      )

      msg
    end

    render partial: 'api/v1/models/message', formats: [:json], locals: { message: @message }
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_could_not_create_error(e.message)
  end

  # F3 — Compartilhar contato.
  # Resolves name/phone from one of three sources (agent | contact | manual),
  # then creates an outgoing Message carrying an Attachment of file_type=:contact.
  # The downstream WhatsApp send pipeline (WAHA Channel::Api) is responsible
  # for shipping the vCard to the recipient.
  def share_contact # rubocop:disable Metrics/MethodLength
    source = share_contact_params[:source].to_s
    return render_could_not_create_error('Invalid source') unless %w[agent contact manual].include?(source)

    name, phone, contact_ref = resolve_share_contact_payload(source)

    return render_could_not_create_error('Phone is required') if phone.blank?
    return render_could_not_create_error('Name is required') if name.blank?

    user = Current.user || @resource

    @message = ActiveRecord::Base.transaction do
      msg = @conversation.messages.create!(
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        message_type: :outgoing,
        content: "#{name} — #{phone}",
        sender: user,
        additional_attributes: { contact: { name: name, phone: phone, source: source, ref: contact_ref }.compact }
      )

      msg.attachments.create!(
        account_id: @conversation.account_id,
        file_type: :contact,
        fallback_title: phone,
        meta: { firstName: name, lastName: '' }
      )

      msg
    end

    render partial: 'api/v1/models/message', formats: [:json], locals: { message: @message }
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_could_not_create_error(e.message)
  end

  private

  def enqueue_waha_status_sync
    inbox = @conversation.inbox
    return unless inbox&.channel_type == 'Channel::Api' && inbox.waha_session_name.present?
    return unless @conversation.messages.exists?(
      message_type: :outgoing, status: :sent, created_at: 1.hour.ago..30.seconds.ago
    )

    Waha::MessageStatusSyncJob.perform_later(@conversation.id)
  end

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :content)
  end

  def location_params
    params.permit(:latitude, :longitude, :address)
  end

  def share_contact_params
    params.permit(:source, :name, :phone, :contact_id, :agent_id)
  end

  # Returns [name, phone_string, ref] tuple. ref is the underlying record id
  # (or nil for "manual"). Phone is normalized to keep digits and a leading "+".
  def resolve_share_contact_payload(source) # rubocop:disable Metrics/AbcSize
    case source
    when 'contact'
      contact = Current.account.contacts.find_by(id: share_contact_params[:contact_id])
      raise ActiveRecord::RecordNotFound, 'Contact not found' if contact.nil?

      [contact.name.to_s, normalize_share_phone(contact.phone_number), contact.id]
    when 'agent'
      agent = Current.account.users.find_by(id: share_contact_params[:agent_id])
      raise ActiveRecord::RecordNotFound, 'Agent not found' if agent.nil?

      raw_phone = share_contact_params[:phone].presence
      [agent.name.to_s, normalize_share_phone(raw_phone), agent.id]
    else # 'manual'
      [share_contact_params[:name].to_s.strip, normalize_share_phone(share_contact_params[:phone]), nil]
    end
  end

  def normalize_share_phone(value)
    digits = value.to_s.gsub(/[^\d+]/, '')
    return '' if digits.blank?

    digits.start_with?('+') ? digits : "+#{digits}"
  end

  def content_update?
    params[:content].present?
  end

  def include_meta?
    return true if params[:include_meta].nil?

    ActiveModel::Type::Boolean.new.cast(params[:include_meta])
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end

  def whatsapp_number_invalid_for_outgoing?
    return false if params[:private].to_s == 'true'
    return false unless whatsapp_inbox?

    message_type = params[:message_type].presence || 'outgoing'
    return false if message_type.to_s == 'incoming'

    contact = @conversation.contact
    contact&.custom_attributes&.[]('whatsapp_number_exists') == false
  end

  def render_whatsapp_invalid_error
    render_could_not_create_error(I18n.t('errors.contacts.whatsapp_validation.not_registered'))
  end

  def waha_echo?
    inbox = @conversation.inbox
    return false unless inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?

    content = params[:content].to_s
    return false unless content.include?(WAHA_ECHO_MARKER_API)

    WAHA_ECHO_MARKERS_SPECIAL.any? { |marker| content.include?(marker) }
  end

  def waha_edit_error_notification?
    inbox = @conversation.inbox
    return false unless inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?

    content = params[:content].to_s
    content.include?(WAHA_ERROR_MARKER) &&
      content.include?(WAHA_ERROR_EVENT)
  end

  # Suprime mensagens postadas pelo app WAHA externo quando ele tem erro
  # interno (retry/timeout/timestamp NaN). O app posta esses erros como Message
  # via API do Chatwoot, poluindo o painel. A mensagem real do WhatsApp já
  # chegou (ou não) por outro caminho — esse texto é só ruído técnico.
  # Exige >= 2 markers pra evitar falso-positivo (ex: agente digitando uma
  # frase legítima que casualmente contém um dos markers).
  def waha_error_message?(content)
    text = content.to_s
    return false if text.blank?

    matches = WAHA_ERROR_MARKERS.count { |marker| text.include?(marker) }
    matches >= 2
  end

  def whatsapp_inbox?
    inbox = @conversation.inbox
    return false unless inbox

    return true if inbox.channel_type == 'Channel::Whatsapp'

    return inbox.channel&.medium == 'whatsapp' if inbox.channel_type == 'Channel::TwilioSms'

    return inbox.waha_session_name.present? if inbox.channel_type == 'Channel::Api'

    false
  end
end
