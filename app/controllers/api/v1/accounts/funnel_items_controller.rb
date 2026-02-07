# frozen_string_literal: true

class Api::V1::Accounts::FunnelItemsController < Api::V1::Accounts::BaseController
  MAX_BACKFILL_ITEMS = 1000

  before_action :funnel
  before_action :funnel_item, except: [:index, :create, :bulk_move]
  before_action :check_authorization

  def index
    backfill_funnel_items
    Rails.logger.debug { "[FunnelItemsController#index] params=#{params.permit(:stage_id, :page, :per_page, :exclude_automation_type).to_h}" }
    scope = policy_scope(funnel.funnel_items).includes(:conversation, :funnel_stage, conversation: [:contact, :inbox, :assignee])
    scope = scope.by_stage(params[:stage_id]) if params[:stage_id].present?

    inbox_ids = funnel.inbox_ids
    if inbox_ids.present? && inbox_ids.is_a?(Array) && inbox_ids.any?
      inbox_ids_array = inbox_ids.map(&:to_i).compact
      scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_ids_array }) if inbox_ids_array.any?
    end

    if params[:exclude_automation_type].present?
      scope = scope.joins(:funnel_stage).where.not(funnel_stages: { automation_type: params[:exclude_automation_type] })
    end

    if params[:stage_id].present?
      per_page = [[(params[:per_page] || 50).to_i, 1].max, 100].min
      page = [(params[:page] || 1).to_i, 1].max
      scope = scope.joins(:conversation).reorder('conversations.last_activity_at DESC')
      scope = scope.limit(per_page).offset((page - 1) * per_page)
    end

    @funnel_items = scope
    Rails.logger.debug { "[FunnelItemsController#index] scope SQL=#{scope.to_sql}; count=#{@funnel_items.size}; sample last_activity_at=#{@funnel_items.first&.conversation&.last_activity_at}" }
    load_last_messages
    @funnel_items = deduplicate_by_contact_phone(@funnel_items)
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

  def bulk_move
    conversation_ids = params[:conversation_ids] || []
    stage_id = params[:stage_id]

    return render json: { error: 'stage_id é obrigatório' }, status: :unprocessable_entity if stage_id.blank?

    stage = funnel.funnel_stages.find(stage_id)
    conversations = Current.account.conversations.where(id: conversation_ids)

    conversations.each do |conv|
      FunnelItems::MoveService.new(
        conversation: conv,
        funnel: funnel,
        funnel_stage: stage,
        moved_by: Current.user
      ).perform
    end

    head :ok
  end

  private

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:funnel_id])
  end

  def funnel_stage
    @funnel_stage ||= funnel.funnel_stages.find(params[:funnel_stage_id] || params.dig(:funnel_item, :funnel_stage_id))
  end

  def conversation
    @conversation ||= Current.account.conversations.find(params[:conversation_id] || params.dig(:funnel_item, :conversation_id))
  end

  def funnel_item
    @funnel_item ||= funnel.funnel_items.find(params[:id])
  end

  def check_authorization
    authorize(@funnel_item || FunnelItem.new(funnel: funnel))
  end

  def backfill_funnel_items
    stages = funnel.funnel_stages.order(:position, :created_at).to_a
    return if stages.empty?

    default_stage = stages.first
    stage_by_automation = stages.index_by(&:automation_type)

    conversations = Current.account.conversations
    conversations = conversations.where(team_id: funnel.team_id) if funnel.team_id.present?

    inbox_ids = funnel.inbox_ids
    if inbox_ids.present? && inbox_ids.is_a?(Array) && inbox_ids.any?
      inbox_ids_array = inbox_ids.map(&:to_i).compact
      conversations = conversations.where(inbox_id: inbox_ids_array) if inbox_ids_array.any?
    end

    # Incluir conversas abertas e resolvidas para que a coluna Resolvidos tenha itens (backfill)
    conversations = conversations.where(status: [:open, :resolved])

    existing_conversation_ids = FunnelItem.where(funnel_id: funnel.id).select(:conversation_id)
    missing_conversations = conversations.where.not(id: existing_conversation_ids).limit(MAX_BACKFILL_ITEMS).to_a

    return if missing_conversations.empty?

    now = Time.current
    moved_by_id = Current.user&.id

    rows = missing_conversations.filter_map do |conv|
      stage = stage_for_conversation(conv, stage_by_automation, default_stage)
      next unless stage

      {
        funnel_id: funnel.id,
        conversation_id: conv.id,
        funnel_stage_id: stage.id,
        moved_by_id: moved_by_id,
        moved_at: now,
        created_at: now,
        updated_at: now
      }
    end

    return if rows.empty?

    FunnelItem.insert_all(rows, unique_by: :index_funnel_items_unique)
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

  def stage_for_conversation(conv, stage_by_automation, default_stage)
    return default_stage unless conv

    case conv.status
    when 'open'
      stage_by_automation['open'] || default_stage
    when 'resolved'
      stage_by_automation['resolved'] || default_stage
    else
      default_stage
    end
  end

  def deduplicate_by_contact_phone(items)
    return items if items.blank?

    by_stage_and_phone = {}
    items.each do |item|
      contact = item.conversation&.contact
      phone = contact&.phone_number
      normalized = normalize_brazilian_phone(phone)
      key = normalized.present? ? "phone:#{normalized}" : "contact:#{item.conversation&.contact_id}"
      stage_key = "#{item.funnel_stage_id}-#{key}"

      existing = by_stage_and_phone[stage_key]
      recency = item.conversation&.last_activity_at || item.created_at || Time.at(0)
      if existing.nil? || recency > (existing.conversation&.last_activity_at || existing.created_at || Time.at(0))
        by_stage_and_phone[stage_key] = item
      end
    end
    by_stage_and_phone.values.sort_by { |i| i.moved_at || i.created_at }.reverse
  end

  def normalize_brazilian_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    digits = digits[0, 4] + '9' + digits[4, 8] if digits.start_with?('55') && digits.length == 12
    digits.presence
  end
end
