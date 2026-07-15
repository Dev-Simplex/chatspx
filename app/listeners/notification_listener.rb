class NotificationListener < BaseListener
  def conversation_bot_handoff(event)
    conversation, account = extract_conversation_and_account(event)
    return if conversation.pending?

    notify_inbox_members(conversation, account)
  end

  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return if conversation.pending?

    notify_inbox_members(conversation, account)
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    assignee = conversation.assignee

    # D4 (D-9): notifica quem PERDEU a conversa. Caminho próprio, ANTES (e fora) do guard
    # notifiable_assignee_change — que é false em self-assign, exatamente o roubo D-9.
    notify_previous_assignee(event, conversation, account)

    # NOTE:  The issue was that when a team change results in an assignee being set to nil,
    # the system was still trying to create a notification about the assignment change,
    # but there was no assignee to notify, causing potential issues in the notification system.
    # We need to debug this properly, but for now no need to pollute the jobs
    return if assignee.blank?
    return if event.data[:notifiable_assignee_change].blank?
    return if conversation.pending?

    NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: assignee,
      account: account,
      primary_actor: conversation
    ).perform
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]

    Messages::MentionService.new(message: message).perform
    Messages::NewMessageNotificationService.new(message: message).perform
  end

  private

  # D4 (D-9): quem PERDEU a conversa é notificado quando outro agente assume (takeover).
  # Fora do guard notifiable_assignee_change (que é false em self-assign — o roubo D-9).
  # Gated pela flag (DD-7): com o Clássico, comportamento fica como hoje.
  def notify_previous_assignee(event, conversation, account)
    return unless account.reply_assignment_gate_enabled?
    return if conversation.pending?

    # Ator REAL (quem executou a reatribuição), capturado no dispatch sync — Current.user é NIL aqui
    # no worker async (EventDispatcherJob/Sidekiq). Ver assignment_handler#assignment_change_event_data.
    actor = takeover_actor(event)
    old_id = takeover_previous_assignee_id(event, actor)
    return if old_id.blank?

    previous_assignee = account.users.find_by(id: old_id) # pode ter saído da conta
    return if previous_assignee.blank?

    NotificationBuilder.new(
      notification_type: 'conversation_unassignment',
      user: previous_assignee,
      account: account,
      primary_actor: conversation,
      # secondary_actor explícito = ator capturado no dispatch (Current.user é NIL no worker async)
      secondary_actor: actor
    ).perform
  end

  # D4: ator que executou a (re)atribuição. Vem do event data (capturado no contexto sync do dispatch);
  # garante que seja um User real (automação/auto-assign passam nil ou AgentBot e não devem "roubar").
  def takeover_actor(event)
    actor = event.data[:assignee_changed_by]
    actor.is_a?(User) ? actor : nil
  end

  # D4: id do assignee anterior elegível para notificação de takeover, ou nil.
  # changed_attributes vem de previous_changes => { 'assignee_id' => [old, new] }.
  def takeover_previous_assignee_id(event, actor)
    old_id, new_id = event.data[:changed_attributes]&.dig('assignee_id')
    return if old_id.blank? || new_id.blank? || old_id == new_id # limbo é assunto do vigia C10
    return if old_id == actor&.id                                # auto-desatribuição não notifica

    old_id
  end

  # Notifica todo membro do inbox. Hoje isso só dispara para quem ligou "Nova conversa"
  # (NotificationBuilder exige opt-in em conversation_creation), mas o opt-in é self-service:
  # sem o guard, qualquer agente pode ligar e passar a receber conversa de outro time.
  # Em conversation_created o team_id normalmente ainda é nil -> a regra cai no ramo permissivo
  # e o comportamento fica igual ao de hoje. Isso é correto: conversa sem time notifica o inbox todo.
  def notify_inbox_members(conversation, account)
    visibility = Conversations::VisibilityService.new(conversation: conversation)
    members = conversation.inbox.members.includes(:notification_settings)
    members.each do |agent|
      next unless visibility.visible_to?(agent)

      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: agent,
        account: account,
        primary_actor: conversation
      ).perform
    end
  end
end
