class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  private

  def agent_can_view_conversation?
    inbox_access? || team_access? || assigned_to_user?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def accessible_inbox_ids
    @accessible_inbox_ids ||= user.inboxes.where(account_id: account&.id).pluck(:id).to_set
  end

  # Membro ∪ supervisionado (D2): o supervisor alcança a conversa do time que
  # supervisiona mesmo sem ser membro do time nem da caixa. Sem supervisão o
  # TeamSupervision devolve só os times de membro — mesmo conjunto de antes.
  def accessible_team_ids
    @accessible_team_ids ||= TeamSupervision.accessible_team_ids(user, account&.id).to_set
  end

  def inbox_access?
    accessible_inbox_ids.include?(record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    accessible_team_ids.include?(record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
