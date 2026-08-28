class ApplicationPolicy
  attr_reader :user_context, :user, :record, :account, :account_user

  def initialize(user_context, record)
    @user_context = user_context
    @user = user_context[:user]
    @account = user_context[:account]
    @account_user = user_context[:account_user]
    @record = record
  end

  def index?
    false
  end

  def show?
    scope.exists?(id: record.id)
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def scope
    Pundit.policy_scope!(user_context, record.class)
  end

  # Supervisor de time não administra a PLATAFORMA (SupervisorSettingsScope).
  # Disponível a todas as policies para que a negação fique escrita ao lado do
  # `administrator?` que ela corrige, em vez de espalhada pelos controllers.
  def supervisor_settings_blocked?
    SupervisorSettingsScope.blocked?(@user, @account)
  end

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
      scope
    end
  end
end
