# frozen_string_literal: true

# Push do chat interno fora da requisição de envio (ver InternalMessages::PushService).
class InternalMessages::PushJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = InternalMessage.find_by(id: message_id)
    return if message.blank? || message.deleted?

    InternalMessages::PushService.new(message).perform
  end
end
