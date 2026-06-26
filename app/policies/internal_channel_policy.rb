# frozen_string_literal: true

# A user may only see/act on internal channels they belong to. Any agent/admin can
# start a DM (create / index the agent list).
class InternalChannelPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def show?
    member?
  end

  def read?
    member?
  end

  def typing?
    member?
  end

  def member?
    return false unless record.is_a?(InternalChannel)

    record.members.exists?(user_id: user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.blank?

      scope.where(account_id: account&.id).for_user(user)
    end
  end
end
