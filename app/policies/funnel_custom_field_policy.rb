# frozen_string_literal: true

class FunnelCustomFieldPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.funnel.account_id == account.id
  end

  def create?
    @account_user&.agent? || @account_user&.administrator?
  end

  def update?
    create? && record.funnel.account_id == account.id
  end

  def destroy?
    create? && record.funnel.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if account.blank?

      scope.joins(:funnel).where(funnels: { account_id: account.id })
    end
  end
end
