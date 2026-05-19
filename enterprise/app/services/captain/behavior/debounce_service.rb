class Captain::Behavior::DebounceService
  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
    @debounce_seconds = assistant.behavior['debounce_seconds'].to_i
  end

  # TTL extra acima do `wait` do job pra evitar race condition: se o Sidekiq
  # atrasar mesmo 1-2s no pickup do job, o TTL Redis já teria expirado e o
  # `stored_token == token` check no DebouncedResponseJob falharia silenciosamente,
  # fazendo o Captain nunca responder. Margem de 30s cobre lag normal de pickup.
  REDIS_TTL_BUFFER_SECONDS = 30

  def schedule
    return if @debounce_seconds < 1

    token = SecureRandom.uuid
    key = redis_key

    Redis::Alfred.set(key, token, nx: false, ex: @debounce_seconds + REDIS_TTL_BUFFER_SECONDS)

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
