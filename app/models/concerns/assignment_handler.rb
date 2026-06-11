module AssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    before_save :ensure_assignee_is_from_team
    before_save :set_assignee_last_changed_at
    after_commit :notify_assignment_change, :process_assignment_changes, :mark_conversation_unread_on_assignment_change
  end

  private

  def ensure_assignee_is_from_team
    if team_id_changed?
      validate_current_assignee_team
      # NÃO auto-atribuir humano do time quando o espelho captain é dono (A2b, triagem D-6:
      # team + espelho na mesma automação — preserva a invariante de exclusividade).
      self.assignee ||= find_assignee_from_team if assignee_agent_bot_id.blank?
    elsif will_save_change_to_assignee_id? && assignee_id.present?
      sync_team_from_assignee
    end
  end

  def sync_team_from_assignee
    agent = User.find_by(id: assignee_id)
    return unless agent

    agent_teams = agent.teams.where(account_id: account_id)
    count = agent_teams.count

    return if count.zero?

    if count == 1
      self.team_id = agent_teams.first.id
    elsif agent_teams.where(id: team_id).none?
      self.team_id = nil
    end
  end

  def set_assignee_last_changed_at
    return unless will_save_change_to_assignee_id? || will_save_change_to_assignee_agent_bot_id?

    self.assignee_last_changed_at = (Time.current if assignee_id.present? && assignee_agent_bot_id.blank?)
  end

  def validate_current_assignee_team
    self.assignee_id = nil if team&.members&.exclude?(assignee)
  end

  def find_assignee_from_team
    return if team&.allow_auto_assign.blank?

    team_members_with_capacity = inbox.member_ids_with_assignment_capacity & team.members.ids
    ::AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: team_members_with_capacity).find_assignee
  end

  def notify_assignment_change
    {
      ASSIGNEE_CHANGED => -> { saved_change_to_assignee_id? },
      TEAM_CHANGED => -> { saved_change_to_team_id? }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, previous_changes)
    end
  end

  def process_assignment_changes
    process_assignment_activities
  end

  def mark_conversation_unread_on_assignment_change
    return unless saved_change_to_assignee_id? || saved_change_to_team_id?

    mark_as_unread!
  end

  def process_assignment_activities
    user_name = Current.user.name if Current.user.present?
    if saved_change_to_team_id?
      create_team_change_activity(user_name)
    elsif saved_change_to_assignee_id?
      create_assignee_change_activity(user_name)
    end
  end

  def self_assign?(assignee_id)
    assignee_id.present? && Current.user&.id == assignee_id
  end
end
