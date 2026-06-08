# frozen_string_literal: true

class KanbanAutomationPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.kanban.account_id == account.id
  end

  def create?
    @account_user&.administrator?
  end

  def update?
    create? && record.kanban.account_id == account.id
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      target = account || Current.account
      return scope.none if target.blank?

      scope.joins(:kanban).where(kanbans: { account_id: target.id })
    end
  end
end
