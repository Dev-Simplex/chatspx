class Messages::NewMessageNotificationService
  pattr_initialize [:message!]

  def perform
    return unless message.notifiable?

    # Único caminho: o último atribuído. A participação é eterna (o ParticipationListener nunca
    # remove o assignee anterior), então notificar participantes enchia o sino de conversas que o
    # usuário só encostou um dia. A aba "Participantes da conversa" segue existindo, mas é informativa.
    notify_conversation_assignee
  end

  private

  delegate :conversation, :sender, :account, to: :message

  def notify_conversation_assignee
    return if conversation.assignee.blank?
    return if already_notified?(conversation.assignee)
    return if conversation.assignee == sender
    return if muted_by_assignee?

    NotificationBuilder.new(
      notification_type: 'assigned_conversation_new_message',
      user: conversation.assignee,
      account: account,
      primary_actor: message.conversation,
      secondary_actor: message
    ).perform
    mark_notified(conversation.assignee)
  end

  # SILENCIAR POR USUARIO (18/09/2026). `user_settings[assignee].muted_until` no futuro corta a
  # notificacao de mensagem nova (sino + push) SO para quem silenciou — gravado pelo
  # PATCH /conversations/:id/user_setting. Nao confundir com `mute!` (ConversationMuteHelpers),
  # que BLOQUEIA o contato e resolve as conversas dele: era o que o botao "Silenciar" do app
  # chamava, e quem so queria parar de ser avisado bloqueava o cliente.
  def muted_by_assignee?
    muted_until = conversation.user_setting_for(conversation.assignee_id)['muted_until']
    return false if muted_until.blank?

    Time.iso8601(muted_until) > Time.current
  rescue ArgumentError
    false
  end

  # The user could already have been notified via a mention or via assignment
  # So we don't need to notify them again
  def already_notified?(user)
    already_notified_user_ids.include?(user.id)
  end

  # O set é memoizado na PRIMEIRA chamada, que acontece em notify_conversation_assignee ANTES de a
  # notificação do assignee existir. Sem registrar o que este próprio service acabou de criar, o
  # assignee que também é participante levava um sino duplicado.
  def mark_notified(user)
    already_notified_user_ids << user.id
  end

  def already_notified_user_ids
    @already_notified_user_ids ||= conversation.notifications
                                               .where(secondary_actor: message)
                                               .pluck(:user_id).to_set
  end
end
