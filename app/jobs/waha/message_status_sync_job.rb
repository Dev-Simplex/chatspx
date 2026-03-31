# frozen_string_literal: true

class Waha::MessageStatusSyncJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    Waha::MessageStatusSyncService.new(conversation).perform
  end
end
