# frozen_string_literal: true

# Leva a menção da nota privada para a DM do chat interno (ver InternalMessages::NoteMentionService).
class InternalMessages::NoteMentionJob < ApplicationJob
  queue_as :default

  def perform(message_id, user_ids)
    message = Message.find_by(id: message_id)
    return if message.blank?

    InternalMessages::NoteMentionService.new(message: message, user_ids: user_ids).perform
  end
end
