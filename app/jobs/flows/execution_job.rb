# frozen_string_literal: true

# Disparo manual/bulk de um Flow (trigger_type: manual). Espelha MacrosExecutionJob: um
# RunnerService por conversa, com o usuário como actor (modo manual — autor = user,
# assign_agent 'self' resolve para ele).
class Flows::ExecutionJob < ApplicationJob
  queue_as :medium

  def perform(flow_id, conversation_ids:, user_id:)
    return unless (flow = Flow.find_by(id: flow_id))
    return unless (user = User.find_by(id: user_id))

    conversations = flow.account.conversations.where(display_id: conversation_ids.to_a)
    return if conversations.blank?

    conversations.each do |conversation|
      Flows::RunnerService.new(flow: flow, conversation: conversation, actor: user).perform
    rescue StandardError => e
      # Isola a conversa: um erro numa não aborta as demais do bulk.
      ChatwootExceptionTracker.new(e, account: flow.account).capture_exception
    end
  end
end
