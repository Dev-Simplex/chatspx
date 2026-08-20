class TeamMemberPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.administrator? || supervisor?
  end

  def destroy?
    @account_user.administrator? || supervisor?
  end

  def update?
    @account_user.administrator? || supervisor?
  end

  private

  # T1: a policy só recebe a CLASSE TeamMember (check_authorization passa o modelo), então
  # ela não tem como saber DE QUAL time se trata. Aqui passa qualquer supervisor; quem
  # confere se ele supervisiona ESTE time — e o pool de quem pode entrar — é o
  # TeamMembersController#authorize_supervisor_membership_change.
  def supervisor?
    TeamSupervision.supervisor?(@user, @account)
  end
end
