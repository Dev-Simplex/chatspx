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
    # Filtra por inbox primeiro
    conversations_by_inbox = conversations.where(inbox: user.inboxes.where(account_id: account.id))
    
    # Se o usuário tem teams, filtra também por team
    if user.teams.any?
      conversations_by_inbox.where('team_id IN (?) OR team_id IS NULL', user.teams.pluck(:id))
    else
      conversations_by_inbox
    end
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
