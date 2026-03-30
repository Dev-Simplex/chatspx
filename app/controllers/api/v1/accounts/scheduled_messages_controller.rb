# frozen_string_literal: true

class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  before_action :set_scheduled_message, except: [:index, :create, :inboxes]
  before_action :check_authorization
  before_action :ensure_pending_message!, only: [:update, :destroy]

  ALLOWED_STATUS_FILTERS = %w[pending sent failed cancelled all].freeze

  def index
    requested_status = normalized_status_filter
    scope = policy_scope(ScheduledMessage)
    scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    scope = apply_status_filter(scope, requested_status)
    return if performed?

    scope = apply_date_filter(scope) unless cursor_mode?
    scope = scope.upcoming if should_apply_upcoming_filter?(requested_status)

    if cursor_mode?
      result = ScheduledMessages::TimelineQueryService.new(
        scope: scope,
        params: params
      ).perform
      @scheduled_messages = result[:items]
      @meta = result[:meta]
    else
      @scheduled_messages = scope
    end

    render 'api/v1/accounts/scheduled_messages/index', formats: [:json]
  end

  def show
    render 'api/v1/accounts/scheduled_messages/show', formats: [:json]
  end

  def create # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    if Current.user.blank?
      render json: { error: 'User not authenticated' }, status: :unauthorized
      return
    end

    if Current.account.blank?
      render json: { error: 'Account not found' }, status: :unauthorized
      return
    end

    sm_params = scheduled_message_params
    unless sm_params
      render json: { error: 'Invalid parameters: send { scheduled_message: { conversation_id or contact_id+inbox_id, message, scheduled_at } }' },
             status: :unprocessable_entity
      return
    end

    conv = ScheduledMessages::ResolveConversationService.new(
      account: Current.account,
      conversation_id: sm_params[:conversation_id] || sm_params['conversation_id'],
      contact_id: sm_params[:contact_id] || sm_params['contact_id'],
      inbox_id: sm_params[:inbox_id] || sm_params['inbox_id']
    ).perform

    inbox_to_use = conv.inbox
    unless inbox_to_use
      render json: { error: 'Conversation does not have an associated inbox' }, status: :unprocessable_entity
      return
    end

    message_content = sm_params[:message] || sm_params['message'] || params[:message]
    scheduled_at_param = sm_params[:scheduled_at] || sm_params['scheduled_at'] || params[:scheduled_at]

    raw_sm = params[:scheduled_message] || params['scheduled_message']
    raw_attachments = raw_sm.present? && (raw_sm[:attachments] || raw_sm['attachments'])
    attachments_param =
      sm_params[:attachments] ||
      sm_params['attachments'] ||
      params.dig(:scheduled_message, :attachments) ||
      params.dig('scheduled_message', 'attachments') ||
      raw_attachments
    attachments_list = Array(attachments_param || []).compact.select do |a|
      a.is_a?(String) || a.respond_to?(:tempfile)
    end

    @scheduled_message = ScheduledMessages::CreateService.new(
      conversation: conv,
      inbox: inbox_to_use,
      message: message_content,
      scheduled_at: scheduled_at_param,
      user: Current.user,
      attachments: attachments_list
    ).perform

    render 'api/v1/accounts/scheduled_messages/create', formats: [:json], status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conversation or inbox not found' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    render json: { error: "Invalid parameters: #{e.message}" }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "ScheduledMessagesController#create: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    render json: { error: 'An unexpected error occurred while creating the scheduled message' }, status: :internal_server_error
  end

  def update
    sm_params = scheduled_message_params(for_update: true)
    if sm_params.blank?
      render json: { error: 'Invalid parameters' }, status: :unprocessable_entity
      return
    end

    has_attachments_key = sm_params.key?(:attachments) || sm_params.key?('attachments')
    attachments = sm_params.delete(:attachments) || sm_params.delete('attachments')
    @scheduled_message.assign_attributes(sm_params)
    @scheduled_message.attachments = Array(attachments).compact if has_attachments_key
    @scheduled_message.save!

    render 'api/v1/accounts/scheduled_messages/update', formats: [:json]
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    @scheduled_message.update!(status: :cancelled)
    head :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def inboxes
    authorize(ScheduledMessage.new, :inboxes?)
    @inboxes = Current.account.inboxes
    render 'api/v1/accounts/scheduled_messages/inboxes', formats: [:json]
  end

  private

  def set_scheduled_message
    @scheduled_message = policy_scope(ScheduledMessage).find(params[:id])
  end

  def scheduled_message_params(for_update: false)
    raw = params[:scheduled_message] || params['scheduled_message']
    return nil if raw.blank?

    permitted_fields = [:message, :scheduled_at, :inbox_id]
    permitted_fields << :conversation_id unless for_update
    permitted_fields << :contact_id unless for_update

    if raw.is_a?(ActionController::Parameters)
      raw.permit(*permitted_fields, attachments: [])
    elsif raw.respond_to?(:to_unsafe_h)
      ActionController::Parameters.new(raw.to_unsafe_h).permit(*permitted_fields, attachments: [])
    else
      ActionController::Parameters.new(raw.to_h).permit(*permitted_fields, attachments: [])
    end
  end

  def normalized_status_filter
    params[:status].to_s.strip
  end

  def apply_status_filter(scope, requested_status = normalized_status_filter)
    return scope if requested_status.blank? || requested_status == 'all'

    unless ALLOWED_STATUS_FILTERS.include?(requested_status)
      render json: { error: "Invalid status. Use: #{ALLOWED_STATUS_FILTERS.join(', ')}" }, status: :unprocessable_entity
      return scope
    end

    scope.where(status: requested_status)
  end

  def apply_date_filter(scope)
    filtered = scope
    from_value = parse_time_param(params[:from])
    to_value = parse_time_param(params[:to])
    filtered = filtered.where('scheduled_messages.scheduled_at >= ?', from_value) if from_value.present?
    filtered = filtered.where('scheduled_messages.scheduled_at <= ?', to_value) if to_value.present?
    filtered
  end

  def parse_time_param(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def should_apply_upcoming_filter?(requested_status)
    return false if cursor_mode?

    requested_status.blank? || requested_status == 'pending'
  end

  def cursor_mode?
    params[:mode].to_s == 'cursor' && Current.account.feature_enabled?('kanban_ux_v2')
  end

  def ensure_pending_message!
    return if @scheduled_message.pending?

    render json: { error: I18n.t('scheduled_messages.errors.only_pending_allowed') }, status: :unprocessable_entity
  end

  def check_authorization
    case action_name
    when 'inboxes'
      authorize(ScheduledMessage.new, :inboxes?)
    when 'index', 'create'
      authorize(ScheduledMessage.new, action_name == 'create' ? :create? : :index?)
    else
      authorize(@scheduled_message)
    end
  end
end
