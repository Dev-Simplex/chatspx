class AgentBotPolicy < ApplicationPolicy
  # index?/show? seguem abertos ao supervisor: a tela da caixa de entrada
  # (BotConfiguration.vue) lista os bots para mostrar qual está ligado. Só a
  # GESTÃO sai do alcance dele.
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    manage?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    manage?
  end

  def destroy?
    manage?
  end

  def avatar?
    manage?
  end

  def reset_access_token?
    manage?
  end

  private

  def manage?
    @account_user.administrator? && !supervisor_settings_blocked?
  end

  # Bloco 4.13: sem esta entrada, `authorize(AgentBot)` levanta Pundit::NotDefinedError e a
  # rota de rotacao morre em 500 para o administrador que tem todo o direito de usa-la —
  # o mesmo modo de falha que `launcher_icon?` ja tinha corrigido em InboxPolicy.
  def reset_secret?
    @account_user.administrator?
  end
end
