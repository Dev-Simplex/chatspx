class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update, unless: :content_update?

  def index
    @include_meta = include_meta?
    @messages = message_finder.perform
    @has_more = message_finder.has_more
  end

  def create
    return render json: { status: 'suppressed' }, status: :ok if waha_edit_echo?
    return render json: { status: 'suppressed' }, status: :ok if waha_edit_error_notification?
    return render_whatsapp_invalid_error if whatsapp_number_invalid_for_outgoing?

    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    if content_update?
      Messages::UpdateContentService.new(message, permitted_params[:content]).perform
    else
      Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    end
    @message = message
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def destroy
    if message.content_type.in?(%w[input_nps input_csat])
      return render json: { error: I18n.t('conversations.messages.undeletable') }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :content)
  end

  def content_update?
    params[:content].present?
  end

  def include_meta?
    return true if params[:include_meta].nil?

    ActiveModel::Type::Boolean.new.cast(params[:include_meta])
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
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

  def waha_edit_echo?
    inbox = @conversation.inbox
    return false unless inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?

    content = params[:content].to_s
    content.include?('Enviado via API') && content.include?('Editado no WhatsApp')
  end

  def waha_edit_error_notification?
    inbox = @conversation.inbox
    return false unless inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?

    content = params[:content].to_s
    content.include?('Não foi possível receber uma mensagem do WhatsApp') &&
      content.include?('message.edited')
  end

  def whatsapp_inbox?
    inbox = @conversation.inbox
    return false unless inbox

    return true if inbox.channel_type == 'Channel::Whatsapp'

    if inbox.channel_type == 'Channel::TwilioSms'
      return inbox.channel&.medium == 'whatsapp'
    end

    if inbox.channel_type == 'Channel::Api'
      return true
    end

    false
  end
end
