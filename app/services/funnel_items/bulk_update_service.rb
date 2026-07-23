# frozen_string_literal: true

# Kanban v2 (Fase 3) — applies a bulk operation (reassign / tag / archive) to a
# set of conversations, reusing Chatwoot's own services so side effects (events,
# webhooks, CSAT gates) stay intact. Each conversation is processed
# independently: one failure (e.g. a resolve gate) skips that row, never aborts
# the batch.
class FunnelItems::BulkUpdateService
  OPERATIONS = %w[reassign tag archive].freeze

  def initialize(account:, conversations:, operation:, performed_by:, params: {})
    @account = account
    @conversations = conversations
    @operation = operation
    @performed_by = performed_by
    @params = params || {}
  end

  def perform
    return { error: "unsupported operation: #{operation}" } unless OPERATIONS.include?(operation)

    processed = 0
    failed = 0
    conversations.find_each do |conversation|
      apply(conversation)
      processed += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("BulkUpdateService #{operation} failed for conversation #{conversation.id}: #{e.message}")
    end

    { operation: operation, processed: processed, failed: failed }
  end

  private

  attr_reader :account, :conversations, :operation, :performed_by, :params

  def apply(conversation)
    case operation
    when 'reassign' then reassign(conversation)
    when 'tag' then tag(conversation)
    when 'archive' then archive(conversation)
    end
  end

  def reassign(conversation)
    # D1 (Fase 3) — guard (d): o bulk do Kanban é a 4ª porta HUMANA de troca de dono
    # (não passa pelo assignments_controller), então precisa do mesmo TakeoverGate
    # dos guards (a)/(b)/(c). Espelha o bulk_actions_job: se o modo de pedido exige
    # aprovação, PULA a linha (não cria pedido em massa — 500 cartões viraria 500
    # pedidos = DoS social no dono). No-op com a flag desligada.
    return if takeover_blocked?(conversation)

    Conversations::AssignmentService.new(
      conversation: conversation,
      assignee_id: params[:assignee_id]
    ).perform
  end

  def takeover_blocked?(conversation)
    return false if params[:assignee_id].blank?

    blocked = Conversations::TakeoverGate.new(
      conversation: conversation,
      actor: performed_by,
      new_assignee_id: params[:assignee_id]
    ).blocked?
    Rails.logger.warn("BulkUpdateService reassign skipped for conversation #{conversation.id} - takeover request required") if blocked
    blocked
  end

  def tag(conversation)
    labels = Array(params[:labels]).map(&:to_s).map(&:strip).reject(&:empty?)
    return if labels.empty?

    conversation.add_labels(labels)
  end

  def archive(conversation)
    return if conversation.resolved?

    Conversations::ToggleStatusService.new(
      conversation: conversation,
      params: { status: 'resolved' },
      user: performed_by
    ).perform
  end
end
