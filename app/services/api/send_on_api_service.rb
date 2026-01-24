class Api::SendOnApiService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Api
  end

  def perform_reply
    # For Channel::Api, messages are sent via webhook only (same as normal user messages)
    # The webhook is automatically triggered by the message.created event
    # No need to do anything here - just let the webhook system handle it
    Rails.logger.info "Api::SendOnApiService: Channel::Api message - webhook will handle delivery automatically"
    # Return immediately - webhook system will send the message
  end
end
