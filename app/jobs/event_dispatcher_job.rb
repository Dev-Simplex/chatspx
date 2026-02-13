class EventDispatcherJob < ApplicationJob
  queue_as :critical

  def perform(event_name, timestamp, data)
    unless data.is_a?(Hash)
      Rails.logger.warn(
        "[EventDispatcherJob] Third argument (data) is not a Hash: #{data.class} - event=#{event_name}. " \
        "Skipping publish to avoid listener crash. Check job argument serialization."
      )
      return
    end
    Rails.configuration.dispatcher.async_dispatcher.publish_event(event_name, timestamp, data)
  end
end
