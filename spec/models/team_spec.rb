require 'rails_helper'

RSpec.describe Team do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:conversations) }
    it { is_expected.to have_many(:team_members) }
  end

  # As 3 tabelas que este fork acrescentou apontando para `teams` nasceram com FK
  # sem on_delete e sem limpeza — cada uma trancava o destroy do time com um 500.
  describe '#destroy' do
    let(:account) { create(:account).tap { |acc| acc.enable_features!('internal_chat') } }
    let(:team) { create(:team, account: account) }

    it 'destroys the team even with a funnel, an internal team-group and assignment history' do
      team_channel = account.internal_channels.team.find_by(team_id: team.id)
      funnel = account.funnels.find_by(team_id: team.id)
      expect(team_channel).to be_present
      expect(funnel).to be_present

      expect { team.destroy! }.not_to raise_error

      # O grupo do chat morre junto (canal `team` sem time é inválido)...
      expect(InternalChannel.exists?(team_channel.id)).to be(false)
      # ...mas o quadro do Kanban sobrevive sem o time, para não sumir com os cartões.
      expect(funnel.reload.team_id).to be_nil
    end

    it 'keeps the assignment history as an audit trail, without the team' do
      history = create(:conversation_assignment_history, account: account, team: team)

      team.destroy!

      expect(history.reload.team_id).to be_nil
    end
  end

  describe '#add_members' do
    let(:team) { FactoryBot.create(:team) }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'handles adds all members and resets cache keys' do
      users = FactoryBot.create_list(:user, 3)
      team.add_members(users.map(&:id))
      expect(team.reload.team_members.size).to eq(3)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).at_least(:once)
                                                                        .with(
                                                                          'account.cache_invalidated',
                                                                          kind_of(Time),
                                                                          account: team.account,
                                                                          cache_keys: team.account.cache_keys
                                                                        )
    end
  end

  describe '#remove_members' do
    let(:team) { FactoryBot.create(:team) }
    let(:users) { FactoryBot.create_list(:user, 3) }

    before do
      team.add_members(users.map(&:id))
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'removes the members and resets cache keys' do
      expect(team.reload.team_members.size).to eq(3)

      team.remove_members(users.map(&:id))
      expect(team.reload.team_members.size).to eq(0)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).at_least(:once)
                                                                        .with(
                                                                          'account.cache_invalidated',
                                                                          kind_of(Time),
                                                                          account: team.account,
                                                                          cache_keys: team.account.cache_keys
                                                                        )
    end
  end
end
