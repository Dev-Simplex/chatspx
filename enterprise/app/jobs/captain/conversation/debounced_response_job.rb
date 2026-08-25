class Captain::Conversation::DebouncedResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant, token)
    key = chave(conversation, assistant)
    stored_token = Redis::Alfred.get(key)

    # Há DUAS razões para não seguir, e só uma é problema:
    #
    #   token DIFERENTE → uma mensagem mais nova reagendou o debounce e este job é o antigo.
    #                     É o mecanismo funcionando; a resposta sai no job novo.
    #   token AUSENTE   → a chave expirou antes de o Sidekiq pegar o job. A resposta se PERDE
    #                     e o cliente fica esperando. Até 25/08/2026 isso não deixava rastro
    #                     nenhum: o `return` mudo era indistinguível de "não havia o que dizer".
    return registrar_perda(conversation, assistant) if stored_token.nil?
    return unless stored_token == token

    Redis::Alfred.delete(key)

    # Token Redis NÃO protege contra troca de dono (chave por conversa+assistant). O
    # re-check do ResponseBuilderJob é a autoridade; aqui só evitamos log 'debounce_fire' falso.
    return unless conversation.assignee_agent_bot&.captain_assistant_id == assistant.id

    registrar(conversation, assistant, 'debounce_fire')
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant)
  end

  private

  def chave(conversation, assistant)
    format(Redis::RedisKeys::CAPTAIN_DEBOUNCE_TOKEN,
           conversation_id: conversation.id, assistant_id: assistant.id)
  end

  # Chave ausente tem duas causas possíveis, e só uma é perda:
  #
  #   (a) o TTL expirou antes do pickup — a resposta se perdeu;
  #   (b) um job MAIS NOVO já disparou e apagou a chave, e este chegou fora de ordem — o
  #       cliente foi atendido, não há perda.
  #
  # Distinguir importa: registrar (b) como perda encheria o log de falso positivo e o sinal
  # viraria ruído, que é como um alerta morre. Um `debounce_fire` posterior ao enfileiramento
  # DESTE job é a prova de (b).
  def registrar_perda(conversation, assistant)
    return if respondido_por_job_mais_novo?(conversation, assistant)

    Rails.logger.warn('[Captain] debounce perdido (token expirou antes do pickup) — ' \
                      "conv=#{conversation.id} assistant=#{assistant.id}: o cliente NAO recebeu resposta.")
    registrar(conversation, assistant, 'debounce_skip', { 'motivo' => 'token_expirado' })
  end

  def respondido_por_job_mais_novo?(conversation, assistant)
    desde = enqueued_at.presence && Time.zone.parse(enqueued_at.to_s)
    return false if desde.blank?

    Captain::AssistantLog.where(conversation_id: conversation.id, captain_assistant_id: assistant.id,
                                event_type: 'debounce_fire', created_at: desde..).exists?
  rescue StandardError
    false
  end

  # Rescue-wrapped: registrar nunca pode derrubar o job. Sem isto, um log inválido mataria a
  # resposta que vinha DEPOIS dele — foi assim que o safety-net de handoff morreu calado antes.
  def registrar(conversation, assistant, evento, payload = {})
    Captain::AssistantLog.create!(
      captain_assistant: assistant, conversation: conversation,
      event_type: evento, payload: payload
    )
  rescue StandardError => e
    Rails.logger.warn("[Captain] assistant_log #{evento} falhou conv=#{conversation&.id}: #{e.message}")
  end
end
