module Enterprise::Message
  private

  def mark_pending_conversation_as_open_for_human_response
    return unless captain_pending_conversation?
    return unless human_response?
    return if private?
    return if template_bootstrap_message?

    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil

    begin
      conversation.open!
      return unless conversation.saved_change_to_status?

      create_captain_auto_open_activity_message
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def captain_pending_conversation?
    return false unless conversation.pending?

    ::CaptainInbox.exists?(inbox_id: conversation.inbox_id)
  end

  # A2c — sucessor estrutural TRANSITÓRIO do skip_after_human_response (revisar na
  # Fase D): humano que responde SEM se atribuir cala a IA soltando o espelho.
  # human_response? reusado de propósito: cobre echo nativo (atendente pelo app
  # WhatsApp Business) e exclui automação/campanha. Mensagem do próprio assistant
  # (sender Captain::Assistant) não passa em human_response? — a IA continua
  # podendo mandar várias em sequência.
  def release_captain_mirror_after_human_reply
    return unless human_response?
    return if private?
    return if template_bootstrap_message?

    mirror = conversation.assignee_agent_bot
    return unless mirror&.captain?

    conversation.captain_release_reason = 'human_reply' # E4: motivo para o watcher de auditoria
    conversation.update!(assignee_agent_bot_id: nil) # IA solta a conversa
  end

  # Fila "Aguardando encerramento": o cliente voltou a falar, então a conversa sai da fila.
  #
  # Mora AQUI, e não no after_commit da conversa, por dois motivos. (1) O sinal certo é "existe
  # incoming novo", não a transição de `waiting_since`: o campo só é populado quando está vazio,
  # então a partir do segundo incoming seguido não há transição nenhuma — e conversa que entra na
  # fila com o cliente tendo falado por último já nasce com ele preenchido. (2) Nesse caso a
  # conversa sequer é salva pelo incoming (`set_conversation_activity` usa update_columns), logo o
  # after_commit não chega a rodar: dali o evento é invisível. Quem sabe que o cliente falou é a
  # mensagem. Custo: uma checagem de chave em memória por incoming, sem query nova.
  def clear_awaiting_closure_after_customer_reply
    return unless incoming?
    return if private?

    conversation.clear_awaiting_closure_on_customer_reply
  end

  def template_bootstrap_message?
    additional_attributes['template_params'].present? &&
      !conversation.messages.incoming.exists?
  end

  def create_captain_auto_open_activity_message
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    )
  end
end
