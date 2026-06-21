# Authorization rules for MessageReaction (PR B1).
#
# Visibility is implicitly scoped by the parent ConversationPolicy — the
# controller authorizes the conversation first, so reactions of any message in
# an accessible conversation are listable and creatable by the agent.
# Destroy requires either ownership (the agent who reacted) or administrator
# rights.
class MessageReactionPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def destroy?
    administrator? || owner?
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def owner?
    return false if user.blank?

    record.user_type == 'User' && record.user_id == user.id
  end
end
