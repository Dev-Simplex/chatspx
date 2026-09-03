class Conversations::DeleteService
  pattr_initialize [:conversation!, :user, :ip]

  def perform
    track_deleted_email_messages
    # ChatSPX (item 23, A6 §1.1): este serviço é novo do upstream e chamava o NOSSO DeleteObjectJob com a
    # assinatura antiga — `perform_later(conversation, user, ip)`, 3 objetos, quando o job espera
    # `(object_type, object_id, user_id, ip)`. A primeira linha do job é
    # `return unless ALLOWED_OBJECT_TYPES.include?(object_type)`, e comparar String com uma
    # instância de Conversation dá `false`: o job retornava na primeira linha, SEM exceção, sem log
    # e sem nada no GlitchTip. Resultado: o usuário clicava em excluir, a API respondia 200 OK, e a
    # conversa continuava lá. Nenhum teste acusava porque não havia erro — havia silêncio.
    # Os outros 7 chamadores do job sempre usaram a forma correta.
    ::DeleteObjectJob.perform_later(conversation.class.name, conversation.id, user&.id, ip)
  end

  private

  def track_deleted_email_messages
    return unless conversation.inbox.email?

    Imap::DeletedMessageTracker.new(inbox: conversation.inbox).record(conversation.messages.incoming.pluck(:source_id))
  end
end
