# frozen_string_literal: true

class KanbanItemPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.kanban.account_id == account.id
  end

  def create?
    @account_user&.agent? || @account_user&.administrator?
  end

  def update?
    create? && record.kanban.account_id == account.id
  end

  def destroy?
    create? && record.kanban.account_id == account.id
  end

  # P3-01
  def quick_reply?
    update?
  end

  # P3-02
  def accept_suggestion?
    update?
  end

  def reject_suggestion?
    update?
  end

  # P3-03
  def send_template?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      target_account = account || Current.account
      return scope.none if target_account.blank?

      scope.joins(:kanban).where(kanbans: { account_id: target_account.id })
    end
  end
end
