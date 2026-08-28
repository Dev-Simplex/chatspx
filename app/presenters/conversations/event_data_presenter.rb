class Conversations::EventDataPresenter < SimpleDelegator
  # Bloco 1.20, asserção (5). `referer_raw` guarda a URL CRUA do visitante — a que nem escapando
  # virou http(s). Ela existe para diagnóstico, continua no banco e continua sendo servida ao
  # agente pela API do painel (`conversations/partials/_conversation.json.jbuilder`). O que ela
  # não pode fazer é sair por AQUI.
  #
  # `push_data` é o payload de PUSH, e o ActionCable o publica para uma lista de tokens que inclui
  # o `pubsub_token` do contact_inbox (`action_cable_listener.rb`, em conversation_created,
  # conversation_updated e conversation_status_changed) — ou seja, para o widget, que roda no
  # navegador do próprio visitante e recebe de volta um texto não validado que veio dele.
  #
  # O filtro fica no presenter, e não no listener, por um motivo medido: o
  # `ActionCableBroadcastJob#prepare_broadcast_data` REMONTA o payload a partir do banco para os
  # eventos de conversa. Um payload filtrado no listener seria descartado e reconstruído com o
  # campo de volta — filtrar lá seria verde no vácuo.
  #
  # Consequência assumida: o mesmo método alimenta `webhook_data`, então o campo também deixa de
  # ir nos webhooks. É o comportamento desejado — dado cru de visitante não deve ser empurrado
  # para endpoint de terceiro, e não há consumidor dele (nenhuma referência no front, painel ou
  # widget). Para a IA o bloqueio já existia em outro ponto do caminho
  # (`Captain::Assistant::RunnerStateHelper::BLOCKED_ADDITIONAL_ATTRIBUTES`).
  PUSH_BLOCKED_ADDITIONAL_ATTRIBUTES = [UrlHelper::REFERER_RAW_KEY].freeze

  def push_data
    {
      additional_attributes: pushable_additional_attributes,
      can_reply: can_reply?,
      channel: inbox.try(:channel_type),
      contact_inbox: contact_inbox,
      id: display_id,
      inbox_id: inbox_id,
      messages: push_messages,
      labels: label_list,
      meta: push_meta,
      status: status,
      custom_attributes: custom_attributes,
      snoozed_until: snoozed_until,
      unread_count: memoized_unread_count,
      first_reply_created_at: first_reply_created_at,
      priority: priority,
      waiting_since: waiting_since.to_i,
      **push_timestamps
    }
  end

  private

  def pushable_additional_attributes
    attributes = additional_attributes
    return attributes unless attributes.is_a?(Hash)

    attributes.except(*PUSH_BLOCKED_ADDITIONAL_ATTRIBUTES)
  end

  def push_messages
    [messages.where(account_id: account_id).chat.includes(attachments: { file_attachment: :blob }).last&.push_event_data].compact
  end

  def push_meta
    {
      sender: contact&.push_event_data,
      assignee: assigned_entity&.push_event_data,
      assignee_type: assignee_type,
      team: team&.push_event_data,
      hmac_verified: contact_inbox&.hmac_verified
    }
  end

  def push_timestamps
    {
      agent_last_seen_at: agent_last_seen_at.to_i,
      contact_last_seen_at: contact_last_seen_at.to_i,
      last_activity_at: last_activity_at.to_i,
      timestamp: last_activity_at.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_f
    }
  end
end
Conversations::EventDataPresenter.prepend_mod_with('Conversations::EventDataPresenter')
