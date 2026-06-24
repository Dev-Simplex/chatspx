# frozen_string_literal: true

class Api::V1::Accounts::FunnelItemsController < Api::V1::Accounts::BaseController
  include Kanban::FunnelItemsBulkActions

  BACKFILL_THROTTLE = 10.minutes

  before_action :funnel
  # bulk_move / bulk_update live in Kanban::FunnelItemsBulkActions (concern).
  before_action :funnel_item, except: [:index, :create, :bulk_move, :bulk_update] # rubocop:disable Rails/LexicallyScopedActionFilter
  before_action :check_authorization

  def index
    scope = policy_scope(funnel.funnel_items).includes(:conversation, :funnel_stage, conversation: [:contact, :inbox, :assignee])

    enqueue_backfill_funnel_items

    if cursor_mode_enabled?
      result = Kanban::FunnelItemsQueryService.new(
        account: Current.account,
        funnel: funnel,
        scope: scope,
        params: params
      ).perform

      @funnel_items = deduplicate_by_contact_phone(result[:items])
      @meta = result[:meta]
    else
      @funnel_items = deduplicate_by_contact_phone(legacy_scope(scope))
    end

    load_last_messages
    load_account_labels
    render 'api/v1/accounts/funnels/funnel_items/index', formats: [:json]
  end

  def create
    @funnel_item = FunnelItems::MoveService.new(
      conversation: conversation,
      funnel: funnel,
      funnel_stage: funnel_stage,
      moved_by: Current.user
    ).perform
    render 'api/v1/accounts/funnels/funnel_items/create', formats: [:json]
  end

  def update
    FunnelItems::MoveService.new(
      conversation: @funnel_item.conversation,
      funnel: funnel,
      funnel_stage: funnel_stage,
      moved_by: Current.user
    ).perform
    @funnel_item.reload
    render 'api/v1/accounts/funnels/funnel_items/update', formats: [:json]
  end

  def destroy
    @funnel_item.destroy!
    head :ok
  end

  # Kanban v2 (Fase 2): merge custom field VALUES into the conversation's
  # custom_attributes. Only this funnel's namespaced keys (funnel_<id>_*) are
  # touched, so unrelated attributes (other integrations) are never clobbered.
  # Blank values clear the key.
  def custom_attributes
    conversation = @funnel_item.conversation
    conversation.update!(custom_attributes: merged_custom_attributes(conversation))

    render json: {
      id: @funnel_item.id,
      conversation_id: conversation.id,
      custom_attributes: funnel_scoped_attributes(conversation.custom_attributes)
    }
  end

  private

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:funnel_id])
  end

  def funnel_stage
    @funnel_stage ||= funnel.funnel_stages.find(params[:funnel_stage_id] || params.dig(:funnel_item, :funnel_stage_id))
  end

  def conversation
    conversation_id = params[:conversation_id] || params.dig(:funnel_item, :conversation_id)
    return @conversation if defined?(@conversation) && @conversation.present?

    @conversation = Current.account.conversations.find_by(id: conversation_id)
    @conversation ||= Current.account.conversations.find_by(display_id: conversation_id)
    raise ActiveRecord::RecordNotFound if @conversation.blank?

    @conversation
  end

  def funnel_item
    @funnel_item ||= funnel.funnel_items.find(params[:id])
  end

  def funnel_attribute_prefix
    "funnel_#{funnel.id}_"
  end

  def funnel_scoped_attributes(attributes)
    (attributes || {}).select { |key, _| key.to_s.start_with?(funnel_attribute_prefix) }
  end

  def merged_custom_attributes(conversation)
    incoming = params.permit(custom_attributes: {}).fetch(:custom_attributes, {}).to_h
    allowed = funnel_scoped_attributes(incoming)
    merged = (conversation.custom_attributes || {}).merge(allowed)
    merged.reject { |key, value| key.to_s.start_with?(funnel_attribute_prefix) && value.to_s.strip.empty? }
  end

  def check_authorization
    authorize(@funnel_item || FunnelItem.new(funnel: funnel))
  end

  def cursor_mode_enabled?
    params[:mode].to_s == 'cursor' && Current.account.feature_enabled?('kanban_cursor_loading')
  end

  def load_last_messages
    conversation_ids = @funnel_items.map(&:conversation_id).uniq
    return if conversation_ids.empty?

    last_messages = Message.where(account_id: Current.account.id, conversation_id: conversation_ids)
                           .non_activity_messages
                           .select('DISTINCT ON (conversation_id) conversation_id, content, processed_message_content, created_at')
                           .reorder('conversation_id, id desc')
    @last_messages_by_conversation_id = last_messages.index_by(&:conversation_id)
  end

  # Account labels are few; one cheap query lets the serializer turn a
  # conversation's denormalized cached_label_list into colored chips with no N+1.
  def load_account_labels
    @labels_by_title = Current.account.labels.index_by { |label| label.title.to_s.downcase }
  end

  def legacy_scope(scope) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    scoped = scope
    scoped = scoped.by_stage(params[:stage_id]) if params[:stage_id].present?

    inbox_ids = funnel.inbox_ids
    if inbox_ids.is_a?(Array) && inbox_ids.any?
      normalized_inbox_ids = inbox_ids.filter_map(&:to_i)
      scoped = scoped.joins(:conversation).where(conversations: { inbox_id: normalized_inbox_ids }) if normalized_inbox_ids.any?
    end

    scoped = scoped.joins(:conversation).where(conversations: { team_id: funnel.team_id }) if funnel.team_id.present?

    if params[:exclude_automation_type].present?
      scoped = scoped.joins(:funnel_stage).where.not(funnel_stages: { automation_type: params[:exclude_automation_type] })
    end

    return scoped if params[:stage_id].blank?

    per_page = (params[:per_page] || 50).to_i.clamp(1, 100)
    page = [(params[:page] || 1).to_i, 1].max
    scoped = scoped.joins(:conversation).reorder('conversations.last_activity_at DESC, conversations.id DESC')
    scoped.limit(per_page).offset((page - 1) * per_page)
  end

  def enqueue_backfill_funnel_items
    cache_key = "kanban:funnel_items:backfill:#{funnel.id}"
    queued = Rails.cache.write(cache_key, true, expires_in: BACKFILL_THROTTLE, unless_exist: true)
    return unless queued

    Kanban::BackfillFunnelItemsJob.perform_later(Current.account.id, funnel.id, Current.user&.id)
  rescue StandardError
    # Best effort: backfill should never block list rendering
  end

  def deduplicate_by_contact_phone(items) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return items if items.blank?

    by_stage_and_phone = {}
    items.each do |item|
      contact = item.conversation&.contact
      phone = contact&.phone_number
      normalized = normalize_brazilian_phone(phone)
      key = if normalized.present?
              "phone:#{normalized}"
            elsif item.conversation&.contact_id.present?
              "contact:#{item.conversation.contact_id}"
            else
              "conversation:#{item.conversation_id}"
            end
      stage_key = "#{item.funnel_stage_id}-#{key}"

      existing = by_stage_and_phone[stage_key]
      recency = item.conversation&.last_activity_at || item.created_at || Time.zone.at(0)
      if existing.nil? || recency > (existing.conversation&.last_activity_at || existing.created_at || Time.zone.at(0))
        by_stage_and_phone[stage_key] = item
      end
    end
    by_stage_and_phone.values.sort_by { |i| i.moved_at || i.created_at }.reverse
  end

  def normalize_brazilian_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    digits = "#{digits[0, 4]}9#{digits[4, 8]}" if digits.start_with?('55') && digits.length == 12
    digits.presence
  end
end
