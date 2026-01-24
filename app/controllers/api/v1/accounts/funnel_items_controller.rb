# frozen_string_literal: true

class Api::V1::Accounts::FunnelItemsController < Api::V1::Accounts::BaseController
  MAX_BACKFILL_ITEMS = 1000

  before_action :funnel
  before_action :funnel_item, except: [:index, :create, :bulk_move]
  before_action :check_authorization

  def index
    backfill_funnel_items
    scope = policy_scope(funnel.funnel_items).includes(:conversation, :funnel_stage, conversation: [:contact, :inbox, :assignee])
    scope = scope.by_stage(params[:stage_id]) if params[:stage_id].present?
    
    # Filtrar por inbox_ids se estiver presente e não vazio
    inbox_ids = funnel.inbox_ids
    if inbox_ids.present? && inbox_ids.is_a?(Array) && inbox_ids.any?
      inbox_ids_array = inbox_ids.map(&:to_i).compact
      if inbox_ids_array.any?
        # Usar joins para filtrar na query SQL, não apenas no includes
        scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_ids_array })
      end
    end
    
    @funnel_items = scope
    load_last_messages
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

    conversations.each do |conversation|
      FunnelItems::MoveService.new(
        conversation: conversation,
        funnel: funnel,
        funnel_stage: stage,
        moved_by: Current.user
      ).perform
    end

    head :ok
  end

  private

  def funnel
    # Usar policy_scope para garantir que apenas funis acessíveis sejam retornados
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

    # Filtrar por inbox_ids se estiver presente e não vazio
    inbox_ids = funnel.inbox_ids
    if inbox_ids.present? && inbox_ids.is_a?(Array) && inbox_ids.any?
      # Converter para array de inteiros para garantir compatibilidade
      inbox_ids_array = inbox_ids.map(&:to_i).compact
      conversations = conversations.where(inbox_id: inbox_ids_array) if inbox_ids_array.any?
    end

    existing_conversation_ids = FunnelItem.where(funnel_id: funnel.id).select(:conversation_id)
    missing_conversations = conversations.where.not(id: existing_conversation_ids)
                                         .limit(MAX_BACKFILL_ITEMS)
                                         .to_a

    return if missing_conversations.empty?

    now = Time.current
    moved_by_id = Current.user&.id

    rows = missing_conversations.filter_map do |conversation|
      stage = stage_for_conversation(conversation, stage_by_automation, default_stage)
      next unless stage

      {
        funnel_id: funnel.id,
        conversation_id: conversation.id,
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

  def stage_for_conversation(conversation, stage_by_automation, default_stage)
    return default_stage unless conversation

    case conversation.status
    when 'open'
      stage_by_automation['open'] || default_stage
    when 'resolved'
      stage_by_automation['resolved'] || default_stage
    else
      default_stage
    end
  end
end
