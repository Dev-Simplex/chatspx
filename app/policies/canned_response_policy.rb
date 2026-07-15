class CannedResponsePolicy < ApplicationPolicy
  def index?
    true # qualquer membro logado lista (o scoping é feito por CannedResponse.with_visibility no controller)
  end

  def create?
    true # agentes e admins podem criar
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def author?
    @record.created_by_id.present? && @record.created_by_id == @account_user.user_id
  end

  def administrator?
    @account_user.administrator?
  end

  def team_member?
    @record.visibility_team? && @account_user.user.teams.exists?(id: @record.team_id)
  end

  # Quem edita/exclui — modelo PERMISSIVO (decisões §1): editar resposta pronta não
  # cascateia, então pública (inclui legadas órfãs) segue livre para qualquer agente.
  def manage?
    return true if administrator?
    return true if @record.visibility_everyone?    # pública: qualquer agente (inclui legadas órfãs)
    return author? if @record.visibility_personal? # privada: só autor
    return team_member? if @record.visibility_team? # de-time: qualquer membro

    false
  end
end
