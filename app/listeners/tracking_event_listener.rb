class TrackingEventListener < BaseListener
  # Bloco 5.03 — os fatos que SO o servidor conhece viram evento de tracking aqui.
  #
  # Hoje ha um: `chatspx_conversation_resolved` (evento #10 do contrato), que e o aceite do bloco.
  # Os eventos #1 a #9 nascem no widget e no store (bloco 5.04, outra trilha) e nao devem ser
  # emitidos daqui tambem: a regra RG4 do plano 25 e "uma emissao por fato", e dois emissores para o
  # mesmo fato e o defeito de juncao que este plano ja pagou caro uma vez.
  #
  # Acrescentar um fato server-side custa um metodo com o mesmo formato — a infraestrutura aceita
  # qualquer nome que obedeca ao contrato.
  #
  # Este listener vive no AsyncDispatcher (roda UMA vez por fato, via EventDispatcherJob) e nunca no
  # SyncDispatcher, que dispararia o mesmo fato duas vezes.
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]

    record_conversation_resolved(conversation, event.timestamp)
  rescue StandardError => e
    # Observabilidade nunca quebra o produto: se o registro falhar, a conversa continua resolvida.
    # E a mesma regra do FlowStepLog desta base — o log e best-effort, o fluxo nao.
    ChatwootExceptionTracker.new(e, account: conversation_account(event)).capture_exception
  end

  private

  def record_conversation_resolved(conversation, resolved_at)
    Tracking::EventRecorder.record!(
      name: 'chatspx_conversation_resolved',
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      contact: conversation.contact,
      occurred_at: resolved_at,
      properties: {
        'resolution' => resolution_of(conversation),
        'duration_s' => resolved_at.to_i - conversation.created_at.to_i
      }
    )
  end

  # Os dois parametros que o contrato declara para o evento #10. `resolution` responde "quem
  # resolveu" com o unico dado que o servidor tem sem inventar: conversa sem responsavel foi
  # resolvida sem humano.
  def resolution_of(conversation)
    conversation.assignee_id.present? ? 'agent' : 'bot'
  end

  def conversation_account(event)
    event.data[:conversation]&.account
  rescue StandardError
    nil
  end
end
