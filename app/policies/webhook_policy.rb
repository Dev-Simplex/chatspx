class WebhookPolicy < ApplicationPolicy
  # Webhooks é uma aba DENTRO da tela de Integrações — some junto com ela para o
  # supervisor de time. `index?` também: nada da tela de atendimento lê esta lista.
  def index?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  def create?
    manage?
  end

  private

  def manage?
    @account_user.administrator? && !supervisor_settings_blocked?
  end
end
