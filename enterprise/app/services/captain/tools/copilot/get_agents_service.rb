class Captain::Tools::Copilot::GetAgentsService < Captain::Tools::BaseTool
  def self.name
    'get_agents'
  end
  description 'List all agents in the account with their availability status'

  def execute
    account_users = @assistant.account.account_users.includes(:user).where(role: [:administrator, :agent])
    return 'No agents found' if account_users.empty?

    results = account_users.map { |au| format_agent(au) }
    "Agents in account:\n#{results.join("\n")}"
  end

  def active?
    user_has_permission('agent_manage') || user_has_permission('report_manage')
  end

  private

  def format_agent(account_user)
    user = account_user.user
    "- #{user.name} (id: #{user.id}, email: #{user.email}, role: #{account_user.role}, availability: #{account_user.availability})"
  end
end
