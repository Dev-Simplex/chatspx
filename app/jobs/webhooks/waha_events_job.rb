# frozen_string_literal: true

# Async handler for WAHA session webhooks that the external "chatwoot" app does
# not forward — currently only `poll.vote` (interactive menu answers). See
# Waha::PollVoteService for the poll-vote handling.
class Webhooks::WahaEventsJob < ApplicationJob
  queue_as :default

  def perform(event:, session:, payload:)
    case event.to_s
    when 'poll.vote', 'poll.vote.failed'
      Waha::PollVoteService.new(session_name: session, payload: payload).perform
    else
      Rails.logger.debug { "[Webhooks::WahaEventsJob] ignoring event #{event.inspect}" }
    end
  end
end
