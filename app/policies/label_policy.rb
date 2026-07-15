class LabelPolicy < ApplicationPolicy
  def index?
    true # qualquer membro logado lista (o scoping é feito por Label.with_visibility no controller)
  end

  def show?
    visible?
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

  def orphan?
    @record.created_by_id.nil?
  end

  def team_member?
    @record.visibility_team? && @account_user.user.teams.exists?(id: @record.team_id)
  end

  # Quem enxerga a etiqueta no catálogo / seletor
  def visible?
    return true if administrator?
    return true if @record.visibility_everyone?
    return author? if @record.visibility_personal?
    return team_member? if @record.visibility_team?

    false
  end

  # Quem edita/exclui — decisões travadas em §1
  def manage?
    return true if administrator?
    return author? if @record.visibility_everyone?  # pública: só autor (ou admin)
    return author? if @record.visibility_personal?  # privada: só autor
    return team_member? if @record.visibility_team? # de-time: qualquer membro

    orphan? # etiquetas legadas sem dono → admin já cobre; agente não
  end
end
