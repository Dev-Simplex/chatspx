# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannels::CreateService do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account, role: :agent) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }

  describe 'group channel' do
    it 'creates a group with the creator and the chosen members' do
      channel = described_class.new(
        account: account, creator: creator, name: 'Suporte', member_ids: [alice.id, bob.id]
      ).perform

      expect(channel).to be_group_chat
      expect(channel.name).to eq('Suporte')
      expect(channel.users).to contain_exactly(creator, alice, bob)
    end
  end

  describe 'team channel' do
    let(:team) { create(:team, account: account) }

    before { team.add_members([alice.id, bob.id]) }

    it 'creates a team channel including the team members and creator' do
      channel = described_class.new(account: account, creator: creator, team: team).perform

      expect(channel).to be_team
      expect(channel.team_id).to eq(team.id)
      expect(channel.users).to include(alice, bob, creator)
    end

    it 'is find-or-create — does not duplicate the team channel' do
      first = described_class.new(account: account, creator: creator, team: team).perform
      expect do
        described_class.new(account: account, creator: alice, team: team).perform
      end.not_to change(InternalChannel, :count)
      expect(described_class.new(account: account, creator: alice, team: team).perform).to eq(first)
    end
  end
end
