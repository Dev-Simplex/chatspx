class Messages::NewMessageNotificationService
  pattr_initialize [:message!]

  def perform
    return unless message.notifiable?

    notify_conversation_assignee
    notify_participating_users
  end

  private

  delegate :conversation, :sender, :account, to: :message

  def notify_conversation_assignee
    return if conversation.assignee.blank?
    return if already_notified?(conversation.assignee)
    return if conversation.assignee == sender

    NotificationBuilder.new(
      notification_type: 'assigned_conversation_new_message',
      user: conversation.assignee,
      account: account,
      primary_actor: message.conversation,
      secondary_actor: message
    ).perform
    mark_notified(conversation.assignee)
  end

  def notify_participating_users
    participating_users = conversation.conversation_participants.includes(:user).map(&:user)
    participating_users -= [sender] if sender.is_a?(User)

    participating_users.uniq.each do |participant|
      next if already_notified?(participant)
      # Participação é eterna (ParticipationListener nunca remove o assignee anterior), então sem
      # este guard o ex-assignee recebe sino de toda mensagem nova de uma conversa que já sumiu da
      # lista dele e responde 403 se ele abrir. Não apagamos a participação: só paramos de notificar.
      next unless visibility.visible_to?(participant)

      NotificationBuilder.new(
        notification_type: 'participating_conversation_new_message',
        user: participant,
        account: account,
        primary_actor: message.conversation,
        secondary_actor: message
      ).perform
    end
  end

  def visibility
    @visibility ||= Conversations::VisibilityService.new(conversation: conversation)
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
