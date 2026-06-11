class Captain::Tools::Copilot::GetAgentWorkloadService < Captain::Tools::BaseTool
  def self.name
    'get_agent_workload'
  end
  description 'Get workload per agent: open conversations count and online/offline status'

  def execute
    account = @assistant.account
    agents = account.account_users.includes(:user).map do |au|
      user = au.user
      open_count = account.conversations.where(assignee_id: user.id, status: :open).count
      "- #{user.name}: #{open_count} open conversations (#{user.availability})"
    end

    agents.any? ? "Agent Workload:\n#{agents.join("\n")}" : 'No agents found'
  end

  def active?
    user_has_permission('report_manage')
  end
end
