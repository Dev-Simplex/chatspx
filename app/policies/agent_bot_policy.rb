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
end
