class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if administrator?

    accessible_conversations
  end

  private

  # Espelho INVERSO em Conversations::VisibilityService (app/services/conversations/visibility_service.rb),
  # que decide a audiência de notificação do sino: dada 1 conversa -> quais usuários.
  # SE VOCÊ MUDAR A REGRA AQUI, MUDE LÁ TAMBÉM — as duas superfícies precisam concordar.
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

  # Single source of truth for the admin check, shared in intent with
  # ConversationFinder#administrator? (enum predicate over the AccountUser role).
  def administrator?
    account_user&.administrator? || false
  end

  # Kept for the Enterprise override (user_has_custom_role?), which still
  # reasons about the raw role string.
  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
