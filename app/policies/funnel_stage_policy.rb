# frozen_string_literal: true

class FunnelStagePolicy < ApplicationPolicy
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
      return scope.none unless account.present?
      # Usar Current.account como fallback se account estiver nil
      target_account = account || Current.account
      return scope.none unless target_account.present?
      scope.joins(:funnel).where(funnels: { account_id: target_account.id })
    end
  end
end


