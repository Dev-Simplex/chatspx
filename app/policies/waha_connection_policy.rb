# frozen_string_literal: true

class WahaConnectionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  # Saúde da linha é para QUEM RESPONDE, não só para quem administra: o agente
  # precisa saber que o WhatsApp daquela caixa caiu antes de digitar. A ação
  # devolve só inbox + status (sem telefone, QR ou credencial).
  def health?
    true
  end

  def create?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def qr_code?
    @account_user.administrator?
  end

  def connect?
    @account_user.administrator?
  end

  def disconnect?
    @account_user.administrator?
  end

  def restart?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
