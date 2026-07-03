# frozen_string_literal: true

class FunnelViewPolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    index? && same_account? && (record.is_shared || owns_record?)
  end

  def create?
    agent_or_admin?
  end

  # Only the owner (or an admin) may change/remove a saved view.
  def update?
    same_account? && (owns_record? || @account_user&.administrator?)
  end

  def destroy?
    update?
  end

  private

  def agent_or_admin?
    @account_user&.agent? || @account_user&.administrator?
  end

  def same_account?
    record.account_id == account.id
  end

  def owns_record?
    record.user_id.present? && record.user_id == @account_user&.user_id
  end
end
