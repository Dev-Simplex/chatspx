class WebhookPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
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
