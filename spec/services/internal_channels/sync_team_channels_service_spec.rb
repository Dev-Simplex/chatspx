# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannels::SyncTeamChannelsService do
  # O grupo de time só nasce (Team#after_create) em conta com a feature ligada.
  let(:account) { create(:account).tap { |acc| acc.enable_features!('internal_chat') } }
  let(:pedro) { create(:user, account: account, role: :agent) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:suporte) { create(:team, account: account, name: 'suporte') }
  let(:dev) { create(:team, account: account, name: 'dev') }

  def team_channel(team)
    account.internal_channels.team.find_by(team_id: team.id)
  end

  describe '#perform' do
    it 'backfills a team-group mirroring the roster for a team that has none' do
      suporte.add_members([pedro.id, ana.id])
      # Simula uma conta antiga (anterior à feature): sem os canais auto-criados.
      account.internal_channels.team.destroy_all

      described_class.new(account: account).perform

      channel = team_channel(suporte)
      expect(channel).to be_present
      expect(channel).to be_team
      expect(channel.name).to eq('suporte')
      expect(channel.users).to contain_exactly(pedro, ana)
    end

    it 'puts a user in every team-group of the teams they belong to (Pedro no suporte E no dev)' do
      suporte.add_members([pedro.id])
      dev.add_members([pedro.id])

      described_class.new(account: account).perform

      expect(team_channel(suporte).users).to include(pedro)
      expect(team_channel(dev).users).to include(pedro)
    end

    it 'is idempotent — a second run adds no members' do
      suporte.add_members([pedro.id, ana.id])
      described_class.new(account: account).perform

      expect { described_class.new(account: account).perform }
        .not_to change(InternalChannelMember, :count)
    end

    it 'reconciles drift: adds missing members and removes strangers' do
      suporte.add_members([pedro.id])
      channel = team_channel(suporte)
      stranger = create(:user, account: account, role: :agent)
      channel.members.create!(user: stranger)                 # intruso (não é do time)
      channel.members.where(user_id: pedro.id).destroy_all    # membro real removido à mão

      described_class.new(account: account, team: suporte).perform

      expect(channel.reload.users).to contain_exactly(pedro)
    end

    it 'renames the team-group when the team name drifts' do
      suporte.add_members([pedro.id])
      channel = team_channel(suporte)
      channel.update!(name: 'nome-defasado')

      described_class.new(account: account, team: suporte).perform

      expect(channel.reload.name).to eq('suporte')
    end
  end
end
