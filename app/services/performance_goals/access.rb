# CHAT-177: ponto UNICO de permissao das metas. Nao usa a ReportPolicy de proposito: mexer nela abriria os
# 11 relatorios de uma vez.
#
#   gerente total  -> administrador sem time supervisionado, ou supervisor da conta (cargo): ve e define tudo
#                     e escolhe quem enxerga o ranking;
#   supervisor de time -> so os times que supervisiona e os atendentes deles (TeamSupervision);
#   atendente      -> conforme account.goals_visibility (managers | own | everyone); nunca define meta.
# No fork, o supervisor de time e ADMINISTRADOR com linha em team_supervisors (ver AccountUser#console_role):
# por isso `administrator?` sozinho nao basta.
class PerformanceGoals::Access
  VISIBILITIES = %w[managers own everyone].freeze

  pattr_initialize [:user!, :account!]

  def full_manager?
    return false if account_user.nil?

    account_user.supervisor? || (account_user.administrator? && supervised_team_ids.empty?)
  end

  def manager?
    full_manager? || supervised_team_ids.any?
  end

  alias can_change_visibility? full_manager?

  def visibility
    VISIBILITIES.include?(account.goals_visibility) ? account.goals_visibility : 'managers'
  end

  # Quem nao gerencia so ve o ranking se a conta liberou.
  def can_view_ranking?
    manager? || visibility != 'managers'
  end

  # nil = todos da conta.
  def managed_user_ids
    full_manager? ? nil : TeamSupervision.manageable_agent_ids(user, account)
  end

  def managed_team_ids
    full_manager? ? nil : supervised_team_ids
  end

  def manages?(target_type, target_id)
    ids = target_type == 'team' ? managed_team_ids : managed_user_ids
    ids.nil? || ids.include?(target_id.to_i)
  end

  # Times de que o atendente participa (o ranking "everyone" dele se limita a eles).
  def member_team_ids
    @member_team_ids ||= user.teams.where(account_id: account.id).pluck(:id)
  end

  private

  def account_user
    @account_user ||= account.account_users.find_by(user_id: user.id)
  end

  def supervised_team_ids
    @supervised_team_ids ||= TeamSupervision.team_ids(user, account)
  end
end
