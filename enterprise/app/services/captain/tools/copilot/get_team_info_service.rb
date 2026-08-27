class Captain::Tools::Copilot::GetTeamInfoService < Captain::Tools::BaseTool
  def self.name
    'get_team_info'
  end
  description 'Get teams information: members, queue size'

  # Esta é a lista de onde o modelo TIRA o id que passa pro `assign_conversation` — enumerar
  # e atribuir são o mesmo par que o handoff da IA já tem. Por isso segue a mesma allowlist
  # (`Account#handoff_teams`, PR #39): time que a conta tirou do roteamento não é oferecido
  # ao modelo. Conta sem a chave => todos os times => nada muda.
  #
  # O que a allowlist esconder é DECLARADO: filtrar em silêncio faria o operador ler a lista
  # como o quadro inteiro e julgar carga de trabalho com número errado.
  def execute
    account = @assistant.account
    listed = account.handoff_teams.includes(:team_members)
    teams = listed.map do |team|
      queue = account.conversations.where(team_id: team.id, status: :open).count
      members = team.team_members.includes(:user).map { |tm| tm.user.name }.join(', ')
      "- #{team.name}: #{team.team_members.count} members (#{members}), #{queue} in queue"
    end

    teams.any? ? "Teams#{omitted_note(account, teams.size)}:\n#{teams.join("\n")}" : 'No teams found'
  end

  def active?
    user_has_permission('team_manage')
  end

  private

  def omitted_note(account, listed_count)
    hidden = account.teams.count - listed_count
    return '' unless hidden.positive?

    " (#{hidden} outside the routing allowlist, not listed)"
  end
end
