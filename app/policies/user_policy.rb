class UserPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.administrator?
  end

  # T1: o supervisor de time renomeia os agentes dos times que supervisiona. Aqui só
  # abrimos a porta do endpoint — a policy recebe a CLASSE User (check_authorization
  # passa o modelo), então ela não sabe QUEM é o alvo nem QUAIS chaves vieram. Quem
  # restringe alvo (membro de time supervisionado, nunca admin) e chaves (só `name`)
  # é o AgentsController#authorize_supervisor_update.
  def update?
    @account_user.administrator? || supervisor?
  end

  # Excluir agente da conta continua exclusivo de admin (D contrato item 3).
  def destroy?
    @account_user.administrator?
  end

  def bulk_create?
    @account_user.administrator?
  end

  private

  def supervisor?
    TeamSupervision.supervisor?(@user, @account)
  end
end
