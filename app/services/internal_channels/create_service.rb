# frozen_string_literal: true

# Chat interno (Módulo B, B2) — creates a group or team channel. For a GROUP the
# creator is always a member. A TEAM channel is find-or-create (one per team) and
# its membership mirrors the team roster EXACTLY (no creator injection) — see
# SyncTeamChannelsService. DMs keep their own FindOrCreateDmService.
class InternalChannels::CreateService
  # The channel kind is inferred: a team is given for team channels, otherwise it
  # is a group. (DMs have their own FindOrCreateDmService.) `creator` is required
  # for groups and ignored for team channels.
  def initialize(account:, creator: nil, name: nil, member_ids: [], team: nil)
    @account = account
    @creator = creator
    @name = name
    @member_ids = Array(member_ids).map(&:to_i)
    @team = team
  end

  def perform
    @team.present? ? find_or_create_team_channel : create_group
  end

  private

  def create_group
    ids = (@member_ids + [@creator.id]).uniq
    users = @account.users.where(id: ids).to_a
    @account.internal_channels.create!(channel_type: :group_chat, name: @name.presence || default_group_name(users)).tap do |channel|
      users.each { |user| channel.members.create!(user: user) }
    end
  end

  def find_or_create_team_channel
    return if @team.blank?

    existing = @account.internal_channels.team.find_by(team_id: @team.id)
    return existing if existing

    # Membership mirrors the team roster exactly (não injeta o criador).
    ids = @team.members.pluck(:id).uniq
    @account.internal_channels.create!(channel_type: :team, team_id: @team.id, name: @team.name).tap do |channel|
      @account.users.where(id: ids).find_each { |user| channel.members.create!(user: user) }
    end
  end

  def default_group_name(users)
    users.map(&:name).take(3).join(', ')
  end
end
