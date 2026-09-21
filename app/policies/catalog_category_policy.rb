# frozen_string_literal: true

# Mesma régua do produto: o atendente lê (a vitrine filtra por categoria), o administrador gere.
class CatalogCategoryPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && same_account?
  end

  def create?
    @account_user&.administrator?
  end

  def update?
    create? && same_account?
  end

  def destroy?
    update?
  end

  private

  # O `authorize` só pergunta quem é o usuário na conta ATUAL, nunca de quem é a categoria.
  def same_account?
    record.account_id == account.id
  end

  # Ver o comentário em CatalogProductPolicy::Scope: sem Scope próprio, `policy_scope` devolve a
  # tabela inteira e a lista vaza entre contas.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if @account_user.blank?

      scope.where(account_id: (account || Current.account)&.id)
    end
  end
end
