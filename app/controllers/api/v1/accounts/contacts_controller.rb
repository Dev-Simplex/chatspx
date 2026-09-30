class Api::V1::Accounts::ContactsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Sift

  WAHA_VALIDATION_SESSION_NAME = ENV.fetch('WAHA_DEFAULT_SESSION', nil).freeze
  # Orcamento TOTAL da validacao no WhatsApp, folgado abaixo do Rack::Timeout (15s).
  # O `read_timeout` do Net::HTTP e por LEITURA, nao pelo total: handshake, cabecalho e corpo
  # podem somar mais que ele sem que nenhuma leitura sozinha estoure. Foi assim que uma sessao
  # morta consumiu 14.995ms e virou 500, no lugar da mensagem amigavel que o codigo pretendia
  # dar (ver o comentario de DEFAULT_TIMEOUT em Waha::ApiService). Um teto total e o unico
  # jeito de a promessa daquele comentario valer de verdade.
  WAHA_VALIDATION_BUDGET_SECONDS = 10
  # Prazo de CADA sessao. Sem ele o teto total nao adianta: a primeira sessao morta gasta
  # os 10s sozinha (medido: 10,4s ate a WAHA devolver o 422) e a sessao viva seguinte nunca
  # chega a ser tentada. Com 4s, uma morta + uma viva fecham em ~4,7s.
  WAHA_SESSION_ATTEMPT_SECONDS = 4
  # Teto de tentativas: uma conta pode ter muitas sessoes e varrer todas transformaria uma
  # falha em espera longa. Duas alternativas ja cobrem o caso real (a escolhida caiu).
  WAHA_MAX_SESSION_ATTEMPTS = 3

  # Estouro do prazo de UMA sessao. Classe propria de proposito: `Timeout::Error` puro e o
  # teto TOTAL, que precisa atravessar o laco e virar mensagem amigavel em vez de ser
  # confundido com "esta sessao falhou, tenta a proxima".
  class SessionAttemptTimeout < StandardError; end
  REVALIDATION_COOLDOWN_SECONDS = 300

  sort_on :email, type: :string
  sort_on :name, internal_name: :order_on_name, type: :scope, scope_params: [:direction]
  sort_on :phone_number, type: :string
  sort_on :last_activity_at, internal_name: :order_on_last_activity_at, type: :scope, scope_params: [:direction]
  sort_on :created_at, internal_name: :order_on_created_at, type: :scope, scope_params: [:direction]
  sort_on :company, internal_name: :order_on_company_name, type: :scope, scope_params: [:direction]
  sort_on :city, internal_name: :order_on_city, type: :scope, scope_params: [:direction]
  sort_on :country, internal_name: :order_on_country_name, type: :scope, scope_params: [:direction]

  RESULTS_PER_PAGE = 15

  before_action :check_authorization
  before_action :set_current_page, only: [:index, :active, :search, :search_for_schedule, :filter]
  before_action :fetch_contact, only: [:show, :update, :destroy, :avatar, :contactable_inboxes, :destroy_custom_attributes, :revalidate_whatsapp]
  before_action :set_include_contact_inboxes, only: [:index, :active, :search, :filter, :show, :update]

  def index
    @contacts = fetch_contacts(resolved_contacts)
    @contacts_count = @contacts.total_count
  end

  def search
    render json: { error: 'Specify search string with parameter q' }, status: :unprocessable_entity if params[:q].blank? && return

    contacts = Current.account.contacts.where(
      'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR contacts.identifier LIKE :search',
      search: "%#{params[:q].strip}%"
    )
    @contacts = fetch_contacts_with_has_more(contacts)
    @duplicates = Contacts::DuplicateFinder.new(account: Current.account, contacts: @contacts).perform
  end

  def search_for_schedule
    result = Contacts::SearchForScheduleService.new(
      account: Current.account,
      query: params[:q],
      page: @current_page,
      per_page: params[:per_page]
    ).perform

    @schedule_contacts = result[:payload]
    @schedule_contacts_count = result[:count]
    @schedule_current_page = result[:current_page]
    @schedule_per_page = result[:per_page]
  end

  def import
    render json: { error: I18n.t('errors.contacts.import.failed') }, status: :unprocessable_entity and return if params[:import_file].blank?

    ActiveRecord::Base.transaction do
      import = Current.account.data_imports.create!(data_type: 'contacts')
      import.import_file.attach(params[:import_file])
    end

    head :ok
  end

  def export
    column_names = params['column_names']
    filter_params = { payload: permitted_filter_params[:payload], label: permitted_filter_params[:label] }
    Account::ContactsExportJob.perform_later(Current.account.id, Current.user.id, column_names, filter_params)
    head :ok, message: I18n.t('errors.contacts.export.success')
  end

  # returns online contacts
  def active
    contacts = Current.account.contacts.where(id: ::OnlineStatusTracker
                  .get_available_contact_ids(Current.account.id))
    @contacts = fetch_contacts(contacts)
    @contacts_count = @contacts.total_count
  end

  def show; end

  def filter
    result = ::Contacts::FilterService.new(Current.account, Current.user, permitted_filter_params).perform
    contacts = result[:contacts]
    @contacts_count = result[:count]
    @contacts = fetch_contacts(contacts)
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  def contactable_inboxes
    @all_contactable_inboxes = Contacts::ContactableInboxesService.new(contact: @contact).get
    @contactable_inboxes = @all_contactable_inboxes.select { |contactable_inbox| policy(contactable_inbox[:inbox]).show? }
  end

  # TODO : refactor this method into dedicated contacts/custom_attributes controller class and routes
  def destroy_custom_attributes
    @contact.custom_attributes = @contact.custom_attributes.excluding(params[:custom_attributes])
    @contact.save!
  end

  def create
    return if should_validate_whatsapp_contact? && !validate_whatsapp_contact!

    ActiveRecord::Base.transaction do
      @contact = Current.account.contacts.new(permitted_params.except(:avatar_url, :validate_whatsapp))
      @contact.save!
      @contact_inbox = build_contact_inbox
      process_avatar_from_url
    end
  end

  def update
    @contact.assign_attributes(contact_update_params)
    @contact.save!
    process_avatar_from_url
  end

  def destroy
    if ::OnlineStatusTracker.get_presence(
      @contact.account.id, 'Contact', @contact.id
    )
      return render_error({ message: I18n.t('contacts.online.delete', contact_name: @contact.name.capitalize) },
                          :unprocessable_entity)
    end

    @contact.destroy!
    head :ok
  end

  def revalidate_whatsapp
    return render_error({ message: I18n.t('errors.contacts.whatsapp_validation.no_phone') }, :unprocessable_entity) if @contact.phone_number.blank?
    return render_error({ message: I18n.t('errors.contacts.whatsapp_validation.cooldown') }, :too_many_requests) if revalidation_on_cooldown?

    number_exists = check_whatsapp_with_fallback
    custom_attributes = @contact.custom_attributes || {}
    custom_attributes['whatsapp_number_exists'] = number_exists
    custom_attributes['whatsapp_last_checked_at'] = Time.zone.now.iso8601
    custom_attributes['whatsapp_validation_source'] = resolve_waha_session_name
    @contact.update!(custom_attributes: custom_attributes)

    render json: { whatsapp_number_exists: number_exists }
  rescue Waha::ApiService::Error
    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.unavailable') }, :unprocessable_entity)
  end

  def avatar
    @contact.avatar.purge if @contact.avatar.attached?
    @contact
  end

  private

  # TODO: Move this to a finder class
  def resolved_contacts
    return @resolved_contacts if @resolved_contacts

    @resolved_contacts = Current.account.contacts.resolved_contacts(use_crm_v2: Current.account.feature_enabled?('crm_v2'))

    @resolved_contacts = @resolved_contacts.tagged_with(params[:labels], any: true) if params[:labels].present?
    @resolved_contacts
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def fetch_contacts(contacts)
    # Build includes hash to avoid separate query when contact_inboxes are needed
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    filtrate(contacts)
      .includes(includes_hash)
      .order(id: :desc)
      .page(@current_page)
      .per(RESULTS_PER_PAGE)
  end

  def fetch_contacts_with_has_more(contacts)
    includes_hash = { avatar_attachment: [:blob] }
    includes_hash[:contact_inboxes] = { inbox: :channel } if @include_contact_inboxes

    # Calculate offset manually to fetch one extra record for has_more check
    offset = (@current_page.to_i - 1) * RESULTS_PER_PAGE
    results = filtrate(contacts)
              .includes(includes_hash)
              .order(id: :desc)
              .offset(offset)
              .limit(RESULTS_PER_PAGE + 1)
              .to_a

    @has_more = results.size > RESULTS_PER_PAGE
    results = results.first(RESULTS_PER_PAGE) if @has_more
    @contacts_count = results.size
    results
  end

  def build_contact_inbox
    return if params[:inbox_id].blank?

    inbox = Current.account.inboxes.find(params[:inbox_id])
    ContactInboxBuilder.new(
      contact: @contact,
      inbox: inbox,
      source_id: params[:source_id]
    ).perform
  end

  def permitted_filter_params
    params.permit(:label, payload: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }])
  end

  def permitted_params
    params.permit(
      :name, :identifier, :email, :phone_number, :avatar, :blocked, :avatar_url, :validate_whatsapp,
      additional_attributes: {}, custom_attributes: {}
    )
  end

  def contact_custom_attributes
    return @contact.custom_attributes.merge(permitted_params[:custom_attributes]) if permitted_params[:custom_attributes]

    @contact.custom_attributes
  end

  def contact_additional_attributes
    return @contact.additional_attributes.merge(permitted_params[:additional_attributes]) if permitted_params[:additional_attributes]

    @contact.additional_attributes
  end

  def contact_update_params
    permitted_params.except(:custom_attributes, :avatar_url, :validate_whatsapp)
                    .merge({ custom_attributes: contact_custom_attributes })
                    .merge({ additional_attributes: contact_additional_attributes })
  end

  def should_validate_whatsapp_contact?
    ActiveModel::Type::Boolean.new.cast(permitted_params[:validate_whatsapp]) &&
      permitted_params[:phone_number].present?
  end

  def validate_whatsapp_contact!
    sanitized_phone = normalize_phone_number_for_waha(permitted_params[:phone_number])
    return true if sanitized_phone.blank?

    response = Timeout.timeout(WAHA_VALIDATION_BUDGET_SECONDS) do
      check_whatsapp_on_any_session(sanitized_phone)
    end
    number_exists = response.fetch('numberExists') { response[:numberExists] }
    return true if number_exists

    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.not_registered') }, :unprocessable_entity)
    false
  rescue Waha::ApiService::Error, Timeout::Error
    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.unavailable') }, :unprocessable_entity)
    false
  rescue ArgumentError
    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.multiple_sessions') }, :unprocessable_entity)
    false
  end

  # Tenta as sessoes candidatas ate uma RESPONDER. O que faz pular para a proxima e falha
  # de SESSAO (fora do ar, nao pareada, WAHA sem rota) ou a sessao estourar o prazo dela.
  #
  # Resposta valida ENCERRA a busca, inclusive `numberExists: false`: isso e a WAHA dizendo
  # que o numero nao tem WhatsApp, e todas as sessoes falam com a mesma rede, entao insistir
  # em outra so trocaria a resposta certa por uma espera.
  def check_whatsapp_on_any_session(phone)
    ultimo_erro = nil

    waha_session_candidates.each do |sessao|
      return attempt_whatsapp_check(sessao, phone)
    rescue Waha::ApiService::Error, SessionAttemptTimeout => e
      Rails.logger.warn("[validacao-whatsapp] sessao #{sessao} nao respondeu (#{e.class}): #{e.message}")
      ultimo_erro = e
    end

    raise ultimo_erro || Waha::ApiService::Error, 'nenhuma sessao WAHA disponivel para validar'
  end

  def attempt_whatsapp_check(session_name, phone)
    Timeout.timeout(WAHA_SESSION_ATTEMPT_SECONDS, SessionAttemptTimeout) do
      waha_service.check_contact_exists(session_name: session_name, phone: phone)
    end
  end

  def waha_session_candidates
    @waha_session_candidates ||= build_waha_session_candidates
  end

  # Ordem: a sessao fixada por ENV primeiro (decisao explicita do admin), depois as que a
  # WAHA diz estarem WORKING, e por fim as demais como ultimo recurso — porque a lista de
  # saude tem cache e pode estar velha, e uma sessao "morta" que voltou ainda e melhor
  # candidata do que nenhuma.
  #
  # A escolha era `session_names.first`, ou seja, ORDEM ALFABETICA, sem olhar se a sessao
  # estava viva. Na Realizare (5 sessoes, 4 WORKING) isso caia sempre na unica quebrada,
  # `Realizare_adm`. Medido em 08/09/2026: sessao morta 10,4s, sessao viva 0,49s.
  def build_waha_session_candidates
    nomes = Current.account.inboxes.where.not(waha_session_name: [nil, ''])
                   .distinct.order(:waha_session_name).pluck(:waha_session_name)
    return Array(WAHA_VALIDATION_SESSION_NAME.presence) if nomes.blank?
    # Uma sessao so: nao ha para onde cair, entao nao vale a chamada extra de saude.
    return nomes if nomes.one?

    fixada = WAHA_VALIDATION_SESSION_NAME if WAHA_VALIDATION_SESSION_NAME.present? && nomes.include?(WAHA_VALIDATION_SESSION_NAME)
    vivas = waha_working_session_names
    ([fixada] + nomes.partition { |nome| vivas.include?(nome) }.flatten).compact.uniq.first(WAHA_MAX_SESSION_ATTEMPTS)
  end

  # Sessoes que a WAHA reporta como WORKING. Uma chamada extra (~0,4s medidos) que evita
  # comecar pela sessao morta. Erra para o lado de NAO travar: se a lista falhar, devolve
  # vazio e a ordem volta a ser a que o admin ve, sem impedir a criacao do contato.
  def waha_working_session_names
    Rails.cache.fetch('waha:working_sessions', expires_in: 30.seconds) do
      Array(waha_service.list_sessions).filter_map do |sessao|
        nome = sessao['name'] || sessao[:name]
        status = sessao['status'] || sessao[:status]
        nome if status.to_s == 'WORKING'
      end
    end
  rescue Timeout::Error
    raise # o teto total e do chamador; engolir aqui gastaria o orcamento e seguiria assim mesmo
  rescue StandardError
    []
  end

  def normalize_phone_number_for_waha(phone_number)
    normalized = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
    normalized.to_s.delete_prefix('+')
  end

  def check_whatsapp_with_fallback
    session_name = resolve_waha_session_name
    raise Waha::ApiService::Error, 'No WAHA session configured for contact' if session_name.blank?

    phones_to_try = whatsapp_phone_candidates
    phones_to_try.each do |phone|
      response = waha_service.check_contact_exists(session_name: session_name, phone: phone)
      return true if response.fetch('numberExists') { response[:numberExists] }
    end
    false
  end

  def resolve_waha_session_name
    return @waha_session_name if @waha_session_name.present?

    candidates = contact_waha_session_candidates
    @waha_session_name = if candidates.many?
                           candidates.find { |name| Waha::SessionStatusCache.usable?(name) } || candidates.first
                         else
                           candidates.first
                         end
  end

  def contact_waha_session_candidates
    inboxes = @contact.contact_inboxes.includes(inbox: :channel).map(&:inbox)
    inboxes.select! { |inbox| %w[Channel::Api Channel::Whatsapp].include?(inbox.channel_type) || inbox.twilio_whatsapp? }
    (inboxes.map(&:waha_session_name) + inboxes.map { |inbox| Waha::GroupLocator.session_from_webhook(inbox) } +
      [ENV.fetch('WAHA_DEFAULT_SESSION', nil)]).filter_map(&:presence).uniq
  end

  def whatsapp_phone_candidates
    normalized = normalize_phone_number_for_waha(@contact.phone_number)
    candidates = [normalized]
    waid = @contact.custom_attributes&.[]('waha_whatsapp_jid')&.sub(/@.*/, '')
    candidates.unshift(waid) if waid.present? && waid != normalized
    candidates.uniq.compact
  end

  def revalidation_on_cooldown?
    last_checked = @contact.custom_attributes&.[]('whatsapp_last_checked_at')
    return false if last_checked.blank?

    Time.zone.parse(last_checked) > REVALIDATION_COOLDOWN_SECONDS.seconds.ago
  end

  def waha_service
    @waha_service ||= Waha::ApiService.new(timeout: 5)
  end

  def set_include_contact_inboxes
    @include_contact_inboxes = if params[:include_contact_inboxes].present?
                                 params[:include_contact_inboxes] == 'true'
                               else
                                 true
                               end
  end

  def fetch_contact
    contact_scope = Current.account.contacts
    contact_scope = contact_scope.includes(contact_inboxes: [:inbox]) if @include_contact_inboxes
    @contact = contact_scope.find(params[:id])
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@contact.class.name, @contact.id, params[:avatar_url]) if params[:avatar_url].present?
  end

  def render_error(error, error_status)
    render json: error, status: error_status
  end
end
