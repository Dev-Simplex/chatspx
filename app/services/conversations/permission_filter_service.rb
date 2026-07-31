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
  #
  # EXCEÇÃO DELIBERADA: a supervisão de time (abaixo) NÃO é espelhada no
  # VisibilityService. O sino foi estreitado de propósito para "só o assignee"
  # (D4 de task/supervisor-de-time.md); supervisor de um time grande viraria spam.
  def accessible_conversations
    scoped = conversations_by_membership
    return scoped if supervised_team_ids.empty?

    # SUPERVISÃO DE TIME (D2): as conversas dos times supervisionados entram no
    # conjunto SEM passar pelo filtro de caixa — quem dá o acesso é a supervisão do
    # time, não a participação na caixa. No-op para quem não supervisiona nada.
    scoped.or(conversations.where(team_id: supervised_team_ids))
  end

  def conversations_by_membership
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

  def supervised_team_ids
    @supervised_team_ids ||= TeamSupervision.team_ids(user, account)
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
