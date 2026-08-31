class Agents::DestroyJob < ApplicationJob
  queue_as :low

  def perform(account_id, user_id)
    account = Account.find_by(id: account_id)
    user = User.find_by(id: user_id)
    return unless account && user

    ActiveRecord::Base.transaction do
      destroy_notification_setting(account, user)
      remove_user_from_teams(account, user)
      remove_user_from_inboxes(account, user)
      unassign_conversations(account, user)
      cleanup_notifications(account, user)
      cleanup_conversation_participants(account, user)
      cleanup_mentions(account, user)
      cleanup_internal_channels(account, user)
    end
  end

  private

  def remove_user_from_inboxes(account, user)
    inboxes = account.inboxes.all
    inbox_members = user.inbox_members.where(inbox_id: inboxes.pluck(:id))
    inbox_members.destroy_all
  end

  # Sair do time já tirava o ex-agente do grupo de time (via TeamMember), mas as DMs
  # e grupos ad-hoc o mantinham como membro para sempre: o nome seguia no roster, o
  # histórico voltava inteiro numa readmissão, e o BroadcastService continuava
  # publicando o conteúdo das mensagens no pubsub_token dele.
  def cleanup_internal_channels(account, user)
    InternalChannelMember.where(user_id: user.id, internal_channel_id: account.internal_channels.select(:id)).destroy_all
  end

  def remove_user_from_teams(account, user)
    teams = account.teams.all
    team_members = user.team_members.where(team_id: teams.pluck(:id))
    team_members.destroy_all
  end

  def destroy_notification_setting(account, user)
    setting = user.notification_settings.find_by(account_id: account.id)
    setting&.destroy!
  end

  def unassign_conversations(account, user)
    # NOTA (Fase E/D-12): bulk update_all não dispara CONVERSATION_UPDATED — as conversas
    # viram órfãs silenciosas. Mitigação estrutural: vigia de órfãs (C10) re-triagem + notifica.
    # rubocop:disable Rails/SkipsModelValidations
    user.assigned_conversations.where(account: account).in_batches.update_all(assignee_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
    supersede_takeover_requests(account, user)
  end

  # D1 (Fase 3): o update_all acima PULA o after_commit que supersederia os
  # pedidos, então faço explícito aqui — senão o dono/solicitante sair da conta
  # deixaria pedidos órfãos pendentes para sempre.
  def supersede_takeover_requests(account, user)
    account.conversation_takeover_requests
           .pending
           .where('owner_id = :id OR requester_id = :id', id: user.id)
           .find_each { |request| request.close!(status: :superseded, source: :system) }
  end

  def cleanup_notifications(account, user)
    Notification.where(account: account, user: user).in_batches.destroy_all
  end

  def cleanup_conversation_participants(account, user)
    conversation_ids = account.conversations.pluck(:id)
    ConversationParticipant.where(user: user, conversation_id: conversation_ids).in_batches.destroy_all
  end

  def cleanup_mentions(account, user)
    conversation_ids = account.conversations.pluck(:id)
    Mention.where(user: user, conversation_id: conversation_ids).in_batches.destroy_all
  end
end
