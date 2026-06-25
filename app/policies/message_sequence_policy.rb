# frozen_string_literal: true

class MessageSequencePolicy < ApplicationPolicy
  # Everyone on the team can see configured sequences (to enroll from a card)...
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && same_account?
  end

  # ...but only admins author them (they send on the customer's behalf).
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
    record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if @account_user.blank?

      scope.where(account_id: (account || Current.account)&.id)
    end
  end
end
