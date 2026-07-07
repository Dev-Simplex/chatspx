# frozen_string_literal: true

# Chat interno — mantém os "grupos de time" espelhando os Teams da conta.
# Para cada time: garante que existe um InternalChannel (channel_type: :team)
# e reconcilia os membros do canal para bater EXATAMENTE com a equipe do time
# (quem entra no time entra no grupo; quem sai, sai). Idempotente e seguro para
# rodar quantas vezes quiser (backfill de contas antigas ou reconciliação).
#
# Uso:
#   InternalChannels::SyncTeamChannelsService.new(account: account).perform        # todos os times
#   InternalChannels::SyncTeamChannelsService.new(account: account, team: t).perform # um time só
class InternalChannels::SyncTeamChannelsService
  def initialize(account:, team: nil)
    @account = account
    @teams = team ? [team] : account.teams.to_a
  end

  # @return [Array<InternalChannel>] os canais de time sincronizados
  def perform
    @teams.filter_map { |team| sync_team(team) }
  end

  private

  def sync_team(team)
    channel = find_or_create_channel(team)
    channel.update!(name: team.name) if channel.name != team.name
    reconcile_members(channel, team)
    channel
  end

  def find_or_create_channel(team)
    @account.internal_channels.team.find_by(team_id: team.id) ||
      @account.internal_channels.create!(channel_type: :team, team_id: team.id, name: team.name)
  end

  # Membros do canal == membros do time (adiciona os que faltam, remove os que
  # sobram). Não injeta "criador": um grupo de time é puramente dirigido pelo time.
  def reconcile_members(channel, team)
    desired = team.members.pluck(:id)
    current = channel.members.pluck(:user_id)

    (desired - current).each { |user_id| channel.members.create!(user_id: user_id) }

    to_remove = current - desired
    channel.members.where(user_id: to_remove).destroy_all if to_remove.any?
  end
end
