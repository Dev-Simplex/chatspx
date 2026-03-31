class Conversations::ActivityMessageJob < ApplicationJob
  queue_as :high

  def perform(conversation_id, message_params)
    return unless (conversation = Conversation.find_by(id: conversation_id))

    conversation.messages.create!(message_params)
  end
end
