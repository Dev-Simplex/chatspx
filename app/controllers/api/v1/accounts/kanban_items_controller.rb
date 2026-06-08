# frozen_string_literal: true

class Api::V1::Accounts::KanbanItemsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  BACKFILL_THROTTLE = 10.minutes

  before_action :kanban
  before_action :kanban_item,
                except: [:index, :create, :bulk_move, :quick_create, :bulk_delete]
  before_action :check_authorization
  before_action :ensure_default_kanbans, only: :index

  def index
    scope = policy_scope(kanban.kanban_items).includes(:conversation, :kanban_stage, conversation: [:contact, :inbox, :assignee])

    result = Kanban::KanbanItemsQueryService.new(
      account: Current.account,
      kanban: kanban,
      scope: scope,
      params: params
    ).perform

    @kanban_items = deduplicate_by_contact_phone(result[:items])
    @meta = result[:meta]

    load_last_messages
    render 'api/v1/accounts/kanbans/kanban_items/index', formats: [:json]
  end

  def create
    @kanban_item = KanbanItems::MoveService.new(
      conversation: conversation,
      kanban: kanban,
      kanban_stage: kanban_stage,
      moved_by: Current.user
    ).perform
    render 'api/v1/accounts/kanbans/kanban_items/create', formats: [:json]
  end

  def update
    KanbanItems::MoveService.new(
      conversation: @kanban_item.conversation,
      kanban: kanban,
      kanban_stage: kanban_stage,
      moved_by: Current.user
    ).perform
    @kanban_item.reload
    render 'api/v1/accounts/kanbans/kanban_items/update', formats: [:json]
  end

  def destroy
    @kanban_item.destroy!
    head :ok
  end

  def quick_create
    stage = kanban.kanban_stages.find(params[:kanban_stage_id] || params[:funnel_stage_id])
    item = Kanbans::QuickCreateService.new(
      account: Current.account,
      kanban_stage: stage,
      contact_query: params[:contact_query].to_s,
      agent: Current.user
    ).call

    if item.present?
      @kanban_item = item
      render 'api/v1/accounts/kanbans/kanban_items/create', formats: [:json]
    else
      render json: { error: 'Não foi possível criar o card' }, status: :unprocessable_entity
    end
  end

  def bulk_move
    conversation_ids = params[:conversation_ids] || []
    item_ids = params[:item_ids] || []
    stage_id = params[:stage_id]

    return render json: { error: 'stage_id is required' }, status: :unprocessable_entity if stage_id.blank?

    stage = kanban.kanban_stages.find(stage_id)
    conversations = collect_bulk_conversations(conversation_ids, item_ids)

    conversations.each do |conv|
      KanbanItems::MoveService.new(
        conversation: conv,
        kanban: kanban,
        kanban_stage: stage,
        moved_by: Current.user
      ).perform
    end

    Kanbans::MetricsService.invalidate(kanban.id)
    head :ok
  end

  def bulk_delete
    item_ids = Array(params[:item_ids]).map(&:to_i).reject(&:zero?)
    return head :ok if item_ids.empty?

    kanban.kanban_items.where(id: item_ids).destroy_all
    Kanbans::MetricsService.invalidate(kanban.id)
    head :ok
  end

  def mark_won
    KanbanItems::MarkWonService.call(
      item: @kanban_item,
      user: Current.user,
      reason: params[:reason],
      value_cents: params[:value_cents],
      source: params[:source],
      detail: params[:detail]
    )
    @kanban_item.reload
    render 'api/v1/accounts/kanbans/kanban_items/update', formats: [:json]
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def mark_lost
    KanbanItems::MarkLostService.call(
      item: @kanban_item,
      user: Current.user,
      reason: params[:reason].to_s,
      tags: params[:tags]
    )
    @kanban_item.reload
    render 'api/v1/accounts/kanbans/kanban_items/update', formats: [:json]
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # KANBAN-P3-01: envia mensagem rápida sem abrir a conversa.
  def quick_reply
    message = KanbanItems::QuickReplyService.call(
      item: @kanban_item,
      user: Current.user,
      content: params[:content],
      private_note: params[:private]
    )
    render json: { ok: true, message: serialize_message(message) }
  rescue KanbanItems::QuickReplyService::ChannelOffline => e
    render json: { error: e.message, code: 'channel_offline' }, status: :service_unavailable
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def serialize_message(message)
    {
      id: message.id,
      content: message.content,
      created_at: message.created_at,
      message_type: message.message_type,
      private: message.private,
      conversation_id: message.conversation_id
    }
  end

  # KANBAN-P3-02: aceita sugestão Captain (move card pro stage sugerido).
  def accept_suggestion
    classification = (@kanban_item.metadata || {})['captain_classification']
    stage_id = classification.is_a?(Hash) ? classification['stage_id'] : nil
    return render(json: { error: 'no_suggestion' }, status: :unprocessable_entity) if stage_id.blank?

    new_stage = kanban.kanban_stages.find_by(id: stage_id)
    return render(json: { error: 'stage_not_found' }, status: :not_found) if new_stage.blank?

    KanbanItems::MoveService.new(
      conversation: @kanban_item.conversation,
      kanban: kanban,
      kanban_stage: new_stage,
      moved_by: Current.user
    ).perform
    persist_classification_feedback('accepted')
    update_feedback_row('approve', new_stage.id)
    @kanban_item.reload
    render 'api/v1/accounts/kanbans/kanban_items/update', formats: [:json]
  end

  def reject_suggestion
    persist_classification_feedback('rejected')
    chosen_stage_id = params[:actual_stage_id].presence || params[:stage_id].presence || @kanban_item.kanban_stage_id
    update_feedback_row('override', chosen_stage_id)
    @kanban_item.reload
    render 'api/v1/accounts/kanbans/kanban_items/update', formats: [:json]
  end

  # KANBAN-P3-03: envia o template configurado da stage (chamada explícita do modal).
  def send_template
    message = KanbanItems::SendTemplateOnMoveService.call(
      item: @kanban_item,
      user: Current.user,
      template_id: params[:template_id],
      variables_override: params[:variables].is_a?(ActionController::Parameters) ? params[:variables].to_unsafe_h : params[:variables]
    )
    render json: { ok: true, message_id: message.id }
  rescue KanbanItems::SendTemplateOnMoveService::TemplateNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue StandardError => e
    Rails.logger.tagged('kanban').error("send_template failed: #{e.class} #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def collect_bulk_conversations(conversation_ids, item_ids)
    conv_ids = Array(conversation_ids).map(&:to_i).reject(&:zero?)
    item_ids_arr = Array(item_ids).map(&:to_i).reject(&:zero?)
    via_items = if item_ids_arr.any?
                  kanban.kanban_items.where(id: item_ids_arr).pluck(:conversation_id)
                else
                  []
                end
    all_ids = (conv_ids + via_items).uniq
    Current.account.conversations.where(id: all_ids)
  end

  def kanban
    @kanban ||= policy_scope(Kanban).find(params[:kanban_id] || params[:funnel_id])
  end

  def kanban_stage
    stage_id = params[:kanban_stage_id] ||
               params[:funnel_stage_id] ||
               params.dig(:kanban_item, :kanban_stage_id) ||
               params.dig(:funnel_item, :funnel_stage_id)
    @kanban_stage ||= kanban.kanban_stages.find(stage_id)
  end

  def conversation
    conversation_id = params[:conversation_id] ||
                      params.dig(:kanban_item, :conversation_id) ||
                      params.dig(:funnel_item, :conversation_id)
    return @conversation if defined?(@conversation) && @conversation.present?

    @conversation = Current.account.conversations.find_by(id: conversation_id)
    @conversation ||= Current.account.conversations.find_by(display_id: conversation_id)
    raise ActiveRecord::RecordNotFound if @conversation.blank?

    @conversation
  end

  def kanban_item
    @kanban_item ||= kanban.kanban_items.find(params[:id])
  end

  def check_authorization
    authorize(@kanban_item || KanbanItem.new(kanban: kanban))
  end

  def load_last_messages
    conversation_ids = @kanban_items.map(&:conversation_id).uniq
    return if conversation_ids.empty?

    last_messages = Message.where(account_id: Current.account.id, conversation_id: conversation_ids)
                           .non_activity_messages
                           .select('DISTINCT ON (conversation_id) conversation_id, content, processed_message_content, created_at')
                           .reorder('conversation_id, id desc')
    @last_messages_by_conversation_id = last_messages.index_by(&:conversation_id)
  end

  # Garante que a conta tenha os kanbans default. Só roda quando o kanban atual
  # está vazio (primeira visita ou conta nova).
  def ensure_default_kanbans
    return unless kanban.kanban_items.empty?

    cache_key = "kanban:kanban_items:backfill:#{kanban.id}"
    queued = Rails.cache.write(cache_key, true, expires_in: BACKFILL_THROTTLE, unless_exist: true)
    return unless queued

    Kanban::BackfillKanbanItemsJob.perform_later(Current.account.id, kanban.id, Current.user&.id)
  rescue StandardError
    # Best effort: backfill should never block list rendering
  end

  def persist_classification_feedback(status)
    meta = @kanban_item.metadata || {}
    classification = (meta['captain_classification'] || {}).merge(
      'feedback' => status,
      'feedback_at' => Time.current.iso8601,
      'feedback_by' => Current.user&.id
    )
    @kanban_item.update(metadata: meta.merge('captain_classification' => classification))
  end

  # KANBAN-P3-02 GAP-FIX: atualiza a tabela kanban_captain_feedbacks.
  def update_feedback_row(verdict, actual_stage_id)
    feedback = KanbanCaptainFeedback.where(kanban_item_id: @kanban_item.id, ai_feedback: 'pending')
                                    .order(created_at: :desc).first
    return if feedback.blank?

    feedback.update(
      ai_feedback: verdict,
      actual_stage_id: actual_stage_id
    )
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').warn("update_feedback_row error: #{e.message}")
  end

  def deduplicate_by_contact_phone(items) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return items if items.blank?

    by_stage_and_phone = {}
    items.each do |item|
      contact = item.conversation&.contact
      phone = contact&.phone_number
      normalized = BrazilianPhoneNormalizer.call(phone)
      key = if normalized.present?
              "phone:#{normalized}"
            elsif item.conversation&.contact_id.present?
              "contact:#{item.conversation.contact_id}"
            else
              "conversation:#{item.conversation_id}"
            end
      stage_key = "#{item.kanban_stage_id}-#{key}"

      existing = by_stage_and_phone[stage_key]
      recency = item.conversation&.last_activity_at || item.created_at || Time.zone.at(0)
      if existing.nil? || recency > (existing.conversation&.last_activity_at || existing.created_at || Time.zone.at(0))
        by_stage_and_phone[stage_key] = item
      end
    end
    by_stage_and_phone.values.sort_by { |i| i.moved_at || i.created_at }.reverse
  end
end
