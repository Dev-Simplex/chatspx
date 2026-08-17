class Api::V1::Accounts::ContactsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Sift

  WAHA_VALIDATION_SESSION_NAME = ENV.fetch('WAHA_DEFAULT_SESSION', nil).freeze
  REVALIDATION_COOLDOWN_SECONDS = 300

  sort_on :email, type: :string
  sort_on :name, internal_name: :order_on_name, type: :scope, scope_params: [:direction]
  sort_on :phone_number, type: :string
  sort_on :last_activity_at, internal_name: :order_on_last_activity_at, type: :scope, scope_params: [:direction]
  sort_on :created_at, internal_name: :order_on_created_at, type: :scope, scope_params: [:direction]
  sort_on :company_name, internal_name: :order_on_company_name, type: :scope, scope_params: [:direction]
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

    response = waha_service.check_contact_exists(session_name: resolve_waha_session_name, phone: sanitized_phone)
    number_exists = response.fetch('numberExists') { response[:numberExists] }
    return true if number_exists

    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.not_registered') }, :unprocessable_entity)
    false
  rescue Waha::ApiService::Error
    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.unavailable') }, :unprocessable_entity)
    false
  rescue ArgumentError
    render_error({ message: I18n.t('errors.contacts.whatsapp_validation.multiple_sessions') }, :unprocessable_entity)
    false
  end

  def resolve_waha_session_name
    @resolve_waha_session_name ||= find_waha_session_name
  end

  def find_waha_session_name
    session_names = Current.account.inboxes.where.not(waha_session_name: [nil, ''])
                           .distinct.order(:waha_session_name).pluck(:waha_session_name)
    return WAHA_VALIDATION_SESSION_NAME if session_names.blank? && WAHA_VALIDATION_SESSION_NAME.present?
    return session_names.first if session_names.one?
    return WAHA_VALIDATION_SESSION_NAME if WAHA_VALIDATION_SESSION_NAME.present? && session_names.include?(WAHA_VALIDATION_SESSION_NAME)

    session_names.first
  end

  def normalize_phone_number_for_waha(phone_number)
    normalized = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
    normalized.to_s.delete_prefix('+')
  end

  def check_whatsapp_with_fallback
    session_name = resolve_waha_session_name
    phones_to_try = whatsapp_phone_candidates
    phones_to_try.each do |phone|
      response = waha_service.check_contact_exists(session_name: session_name, phone: phone)
      return true if response.fetch('numberExists') { response[:numberExists] }
    end
    false
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
    @waha_service ||= Waha::ApiService.new
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

Api::V1::Accounts::ContactsController.prepend_mod_with('Api::V1::Accounts::ContactsController')
