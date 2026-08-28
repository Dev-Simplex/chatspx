class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      user.assigned_inboxes
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)

    Current.user.assigned_inboxes.exists?(id: record.id)
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def campaigns?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def set_agent_bot?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  # Bloco 3.19: mesma alcada do avatar — quem pode trocar a cara da inbox pode tirar a foto do
  # lancador. Sem esta entrada, `authorize(Inbox)` levanta `Pundit::NotDefinedError` e a rota morre
  # com 500 para o administrador que tem todo o direito de usa-la.
  def launcher_icon?
    @account_user.administrator?
  end

  def sync_templates?
    @account_user.administrator?
  end

  def health?
    @account_user.administrator?
  end
end
