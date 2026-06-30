class AccountIntegrationPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def test_connection?
    @account_user.administrator?
  end
end
