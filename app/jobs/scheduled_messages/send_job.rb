# frozen_string_literal: true

module ScheduledMessages
  class SendJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(scheduled_message_id)
      scheduled_message = ScheduledMessage.find(scheduled_message_id)

      return if scheduled_message.sent? || scheduled_message.cancelled?
      return if scheduled_message.scheduled_at > Time.current

      ScheduledMessages::SendService.new(scheduled_message: scheduled_message).perform
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "ScheduledMessage #{scheduled_message_id} not found"
    end
  end
end
