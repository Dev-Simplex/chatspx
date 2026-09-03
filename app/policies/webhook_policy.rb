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

  # Bloco 4.14. As tres sao de administrador pelo mesmo motivo das demais: rotacao troca
  # uma credencial, e o log de entregas carrega o PAYLOAD — que tem dado de conversa e de
  # contato. Sem estas definicoes o Pundit levanta NotDefinedError e a rota devolve 500,
  # que foi exatamente o que o teste pegou.
  def rotate_secret?
    @account_user.administrator?
  end

  def deliveries?
    @account_user.administrator?
  end

  def replay?
    @account_user.administrator?
  end
end
