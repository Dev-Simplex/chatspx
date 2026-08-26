class Captain::Behavior::DebounceService
  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
    @debounce_seconds = assistant.behavior['debounce_seconds'].to_i
  end

  # TTL extra acima do `wait` do job. Se o token expirar antes de o Sidekiq pegar o job, o
  # `stored_token == token` do DebouncedResponseJob falha e o Captain NUNCA RESPONDE —
  # silenciosamente.
  #
  # Era 30s, calibrado para "lag normal de pickup". Não cobriu a realidade: medido na prod da
  # Tozi em 25/08/2026, o atraso mediano de pickup é de **22 segundos** para um debounce de 15,
  # e o p99 do dia foi de **104s**. Em 24h, 18 de 533 debounces (3,4%) foram executados depois
  # do TTL — cada um é um cliente que escreveu e não recebeu resposta. O caso que motivou:
  # conversa 30869, cliente pedindo o financeiro, IA muda, transferência manual 1h39 depois.
  #
  # O número passa a 300s porque o TTL nunca foi um prazo — é rede. Quem deduplica é a
  # SOBRESCRITA da chave (mensagem nova gera token novo no mesmo key) e o `delete` de quem
  # consome. Um TTL folgado não deixa job velho revivendo: o token dele já não é o guardado.
  # O único papel do TTL é não vazar chave quando o job morre de vez — e para isso 5 minutos
  # cumprem o mesmo que 30 segundos, sem fazer a corretude depender da latência da fila.
  REDIS_TTL_BUFFER_SECONDS = 300

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
