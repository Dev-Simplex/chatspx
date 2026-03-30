class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    conversations_by_inbox = conversations.where(inbox: user.inboxes.where(account_id: account.id))
    if user_team_ids.any?
      conversations_by_inbox.where('team_id IN (?) OR team_id IS NULL', user_team_ids)
    else
      conversations_by_inbox
    end
  end

  def user_team_ids
    @user_team_ids ||= user.teams.where(account_id: account.id).pluck(:id)
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
