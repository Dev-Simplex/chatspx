class Captain::Behavior::DebounceService
  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
    @debounce_seconds = assistant.behavior['debounce_seconds'].to_i
  end

  def schedule
    return if @debounce_seconds < 1

    token = SecureRandom.uuid
    key = redis_key

    Redis::Alfred.set(key, token, nx: false, ex: @debounce_seconds)

    Captain::Conversation::DebouncedResponseJob.set(wait: @debounce_seconds.seconds).perform_later(
      @conversation,
      @assistant,
      token
    )
  end

  private

  def redis_key
    format(Redis::RedisKeys::CAPTAIN_DEBOUNCE_TOKEN,
           conversation_id: @conversation.id,
           assistant_id: @assistant.id)
  end
end
