class Agents::DestroyJob < ApplicationJob
  queue_as :low

  def perform(account, user)
    ActiveRecord::Base.transaction do
      destroy_notification_setting(account, user)
      remove_user_from_teams(account, user)
      remove_user_from_inboxes(account, user)
      unassign_conversations(account, user)
      cleanup_notifications(account, user)
      cleanup_conversation_participants(account, user)
      cleanup_mentions(account, user)
    end
  end

  private

  def remove_user_from_inboxes(account, user)
    inboxes = account.inboxes.all
    inbox_members = user.inbox_members.where(inbox_id: inboxes.pluck(:id))
    inbox_members.destroy_all
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
    # rubocop:disable Rails/SkipsModelValidations
    user.assigned_conversations.where(account: account).in_batches.update_all(assignee_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
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
