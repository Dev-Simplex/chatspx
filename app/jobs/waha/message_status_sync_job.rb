# frozen_string_literal: true

class Waha::MessageStatusSyncJob < ApplicationJob
  queue_as :default

  COOLDOWN = 3.seconds

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    cache_key = "waha_msg_status_sync:#{conversation_id}"
    return if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: COOLDOWN)
    Waha::MessageStatusSyncService.new(conversation).perform
  end
end
