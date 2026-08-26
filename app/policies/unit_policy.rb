class UnitPolicy < ApplicationPolicy
  # Leitura é aberta: a unidade alimenta a tela de atendimento (o atendente precisa
  # saber o horário da filial para responder o cliente). LER NÃO É ADMINISTRAR.
  def index?
    true
  end

  def show?
    true
  end

  # Gestão é de administrador. Supervisor de time NÃO é bloqueado aqui de propósito:
  # unidade não é configuração de plataforma — não entra nas seis telas de
  # SupervisorSettingsScope. Ele administra unidade como administra caixa e time.
  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
