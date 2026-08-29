class AgentBotPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def reset_access_token?
    @account_user.administrator?
  end

  # Bloco 4.13: sem esta entrada, `authorize(AgentBot)` levanta Pundit::NotDefinedError e a
  # rota de rotacao morre em 500 para o administrador que tem todo o direito de usa-la —
  # o mesmo modo de falha que `launcher_icon?` ja tinha corrigido em InboxPolicy.
  def reset_secret?
    @account_user.administrator?
  end
end
