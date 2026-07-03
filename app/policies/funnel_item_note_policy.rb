# frozen_string_literal: true

class FunnelItemNotePolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def create?
    agent_or_admin?
  end

  # Only the author (or an admin) may delete a note.
  def destroy?
    agent_or_admin? && (record.user_id == @account_user&.user_id || @account_user&.administrator?)
  end

  private

  def agent_or_admin?
    @account_user&.agent? || @account_user&.administrator?
  end
end
