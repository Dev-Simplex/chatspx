# frozen_string_literal: true

class FunnelAutomationPolicy < ApplicationPolicy
  # Everyone on the team can see what's configured...
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && same_account?
  end

  # ...but only admins author automations (they move/assign/webhook on their own).
  def create?
    @account_user&.administrator?
  end

  def update?
    create? && same_account?
  end

  def destroy?
    update?
  end

  private

  def same_account?
    record.funnel.account_id == account.id
  end
end
