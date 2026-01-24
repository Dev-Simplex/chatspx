# frozen_string_literal: true

class ScheduledMessagePolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.conversation.account_id == account.id
  end

  def create?
    @account_user&.agent? || @account_user&.administrator?
  end

  def update?
    create? && record.conversation.account_id == account.id
  end

  def destroy?
    create? && record.conversation.account_id == account.id
  end

  def inboxes?
    @account_user&.agent? || @account_user&.administrator?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(conversation: :account).where(conversations: { account_id: account.id })
    end
  end
end

