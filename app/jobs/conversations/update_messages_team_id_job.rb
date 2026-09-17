# frozen_string_literal: true

class Conversations::UpdateMessagesTeamIdJob < ApplicationJob
  BATCH_SIZE = 1_000

  queue_as :low

  # Reads conversation.team_id at execution time (not from job args). When the conversation
  # is reassigned multiple times in quick succession, several jobs are enqueued; previously
  # each carried a frozen team_id and could overwrite a newer value out of order. By reading
  # the current state here, the last write always wins.
  #
  # Second arg is kept for backward compatibility with jobs already in the Sidekiq queue.
  def perform(conversation_id, _legacy_team_id = nil)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    # O cursor por id avanca sem reler a conversa inteira a cada lote.
    conversation.all_messages.where('messages.team_id IS DISTINCT FROM ?', conversation.team_id).in_batches(of: BATCH_SIZE) do |batch|
      batch.update_all(team_id: conversation.team_id) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
