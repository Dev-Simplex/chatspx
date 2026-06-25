# frozen_string_literal: true

# Enrolling / unenrolling a conversation is an agent-level action (it is part of
# handling the conversation), unlike authoring the sequence itself (admin-only).
class MessageSequenceEnrollmentPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def create?
    index?
  end

  def destroy?
    index? && record.message_sequence.account_id == account.id
  end
end
