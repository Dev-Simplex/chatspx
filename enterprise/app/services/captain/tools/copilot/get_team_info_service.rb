class Captain::Tools::Copilot::GetTeamInfoService < Captain::Tools::BaseTool
  def self.name
    'get_team_info'
  end
  description 'Get teams information: members, queue size'

  def execute
    account = @assistant.account
    teams = account.teams.includes(:team_members).map do |team|
      queue = account.conversations.where(team_id: team.id, status: :open).count
      members = team.team_members.includes(:user).map { |tm| tm.user.name }.join(', ')
      "- #{team.name}: #{team.team_members.count} members (#{members}), #{queue} in queue"
    end

    teams.any? ? "Teams:\n#{teams.join("\n")}" : 'No teams found'
  end

  def active?
    user_has_permission('team_manage')
  end
end
