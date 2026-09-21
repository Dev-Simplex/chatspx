# frozen_string_literal: true

# Ler é do atendente, administrar é do administrador. O atendente PRECISA ler: é ele quem manda o
# produto na conversa (C8). Cadastrar, mexer em preço e apagar continuam sendo de administrador.
class CatalogProductPolicy < ApplicationPolicy
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

  def destroy_image?
    update?
  end

  private

  # O `authorize` só pergunta quem é o usuário na conta ATUAL, nunca de quem é o produto. Sem esta
  # comparação, trocar o id na URL editaria produto de outra conta.
  def same_account?
    record.account_id == account.id
  end

  # Sem Scope próprio a policy herda o de ApplicationPolicy, cujo `resolve` devolve o escopo CRU:
  # `policy_scope(CatalogProduct)` viraria a tabela inteira, e a lista mostraria produto alheio.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if @account_user.blank?

      scope.where(account_id: (account || Current.account)&.id)
    end
  end
end
