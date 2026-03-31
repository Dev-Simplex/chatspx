# frozen_string_literal: true

class Conversations::UpdateMessagesTeamIdJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, team_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    conversation.all_messages.update_all(team_id: team_id) # rubocop:disable Rails/SkipsModelValidations
  end
end
