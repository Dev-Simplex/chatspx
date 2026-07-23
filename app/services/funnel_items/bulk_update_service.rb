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
    Conversations::AssignmentService.new(
      conversation: conversation,
      assignee_id: params[:assignee_id]
    ).perform
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
