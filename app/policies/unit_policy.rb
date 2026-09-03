class UnitPolicy < ApplicationPolicy
  # Leitura é aberta: a unidade alimenta a tela de atendimento (o atendente precisa
  # saber o horário da filial para responder o cliente). LER NÃO É ADMINISTRAR.
  # Aberta DENTRO da conta — quem delimita a conta é o Scope, aqui embaixo.
  def index?
    true
  end

  def show?
    same_account?
  end

  # Gestão é de administrador. Supervisor de time NÃO é bloqueado aqui de propósito:
  # unidade não é configuração de plataforma — não entra nas seis telas de
  # SupervisorSettingsScope. Ele administra unidade como administra caixa e time.
  def create?
    @account_user.administrator?
  end

  def update?
    create? && same_account?
  end

  def destroy?
    update?
  end

  private

  # O `authorize` só pergunta se quem chama é administrador da conta ATUAL — nunca de
  # quem é a unidade. Sem esta comparação, trocar o id na URL editava unidade alheia.
  def same_account?
    record.account_id == account.id
  end

  # Sem Scope próprio a policy herda o de ApplicationPolicy, cujo `resolve` devolve o
  # escopo CRU: `policy_scope(Unit)` virava `Unit` inteiro, sem `where` nenhum. A lista
  # mostrava unidade de outra conta, e o `find` do controller alcançava outra conta.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if @account_user.blank?

      scope.where(account_id: (account || Current.account)&.id)
    end
  end
end
