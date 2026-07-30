# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamSupervision do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  describe '.team_ids' do
    it 'returns an empty list when the user supervises nothing (caminho inerte)' do
      expect(described_class.team_ids(agent, account)).to eq([])
    end

    it 'returns the supervised team ids' do
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.team_ids(agent, account)).to contain_exactly(team.id)
    end

    it 'scopes the ids to the given account' do
      foreign_team = create(:team, account: other_account)
      create(:account_user, user: agent, account: other_account, role: :agent)
      create(:team_supervisor, team: team, user: agent)
      create(:team_supervisor, team: foreign_team, user: agent)

      expect(described_class.team_ids(agent, account)).to contain_exactly(team.id)
      expect(described_class.team_ids(agent.reload, other_account)).to contain_exactly(foreign_team.id)
    end

    it 'accepts an account id instead of an account object' do
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.team_ids(agent, account.id)).to contain_exactly(team.id)
    end

    it 'returns an empty list without a user (job/widget/public API)' do
      expect(described_class.team_ids(nil, account)).to eq([])
    end

    it 'returns an empty list for an agent bot' do
      expect(described_class.team_ids(create(:agent_bot), account)).to eq([])
    end

    it 'returns an empty list when the account is blank' do
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.team_ids(agent, nil)).to eq([])
    end
  end

  describe '.supervises?' do
    before { create(:team_supervisor, team: team, user: agent) }

    it 'is true for a supervised team' do
      expect(described_class.supervises?(agent, team.id, account)).to be(true)
    end

    it 'is false for a team the user does not supervise' do
      expect(described_class.supervises?(agent, other_team.id, account)).to be(false)
    end

    it 'is false when the conversation has no team' do
      expect(described_class.supervises?(agent, nil, account)).to be(false)
    end

    it 'accepts a team id as a string' do
      expect(described_class.supervises?(agent, team.id.to_s, account)).to be(true)
    end
  end

  describe '.supervisor?' do
    it 'is false when nobody was marked as supervisor' do
      expect(described_class.supervisor?(agent, account)).to be(false)
    end

    it 'is true once the user supervises at least one team' do
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.supervisor?(agent, account)).to be(true)
    end
  end

  describe '.manageable_agent_ids' do
    it 'returns an empty list when the user supervises nothing (caminho inerte)' do
      create(:team_member, team: team, user: create(:user, account: account, role: :agent))

      expect(described_class.manageable_agent_ids(agent, account)).to eq([])
    end

    it 'returns the members of the supervised team' do
      member = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: member)
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.manageable_agent_ids(agent, account)).to contain_exactly(member.id)
    end

    it 'unites the members of every supervised team without duplicating' do
      member = create(:user, account: account, role: :agent)
      other_member = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: member)
      create(:team_member, team: other_team, user: member)
      create(:team_member, team: other_team, user: other_member)
      create(:team_supervisor, team: team, user: agent)
      create(:team_supervisor, team: other_team, user: agent)

      expect(described_class.manageable_agent_ids(agent, account)).to contain_exactly(member.id, other_member.id)
    end

    it 'leaves out the members of a team the user does not supervise' do
      outsider = create(:user, account: account, role: :agent)
      create(:team_member, team: other_team, user: outsider)
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.manageable_agent_ids(agent, account)).to eq([])
    end

    it 'does not include the supervisor himself when he is not a member' do
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.manageable_agent_ids(agent, account)).not_to include(agent.id)
    end

    it 'scopes the supervision to the given account' do
      foreign_team = create(:team, account: other_account)
      foreign_member = create(:user, account: other_account, role: :agent)
      create(:team_member, team: foreign_team, user: foreign_member)
      create(:account_user, user: agent, account: other_account, role: :agent)
      create(:team_supervisor, team: foreign_team, user: agent)

      expect(described_class.manageable_agent_ids(agent, account)).to eq([])
    end

    it 'returns an empty list without a user' do
      expect(described_class.manageable_agent_ids(nil, account)).to eq([])
    end
  end

  describe '.accessible_team_ids' do
    it 'returns the teams the user is a member of' do
      create(:team_member, team: team, user: agent)

      expect(described_class.accessible_team_ids(agent, account)).to contain_exactly(team.id)
    end

    it 'unites membership with supervision' do
      create(:team_member, team: team, user: agent)
      create(:team_supervisor, team: other_team, user: agent)

      expect(described_class.accessible_team_ids(agent, account)).to contain_exactly(team.id, other_team.id)
    end

    it 'does not duplicate a team the user is both member and supervisor of' do
      create(:team_member, team: team, user: agent)
      create(:team_supervisor, team: team, user: agent)

      expect(described_class.accessible_team_ids(agent, account)).to contain_exactly(team.id)
    end

    it 'returns an empty list without a user' do
      expect(described_class.accessible_team_ids(nil, account)).to eq([])
    end
  end

  describe 'User#supervised_team_ids_for' do
    it 'memoizes the answer for the request' do
      create(:team_supervisor, team: team, user: agent)
      expect(agent.supervised_team_ids_for(account.id)).to contain_exactly(team.id)

      create(:team_supervisor, team: other_team, user: agent)
      expect(agent.supervised_team_ids_for(account.id)).to contain_exactly(team.id)
    end

    it 'refreshes after the cache is reset' do
      create(:team_supervisor, team: team, user: agent)
      agent.supervised_team_ids_for(account.id)

      create(:team_supervisor, team: other_team, user: agent)
      agent.reset_supervised_team_ids_cache

      expect(agent.supervised_team_ids_for(account.id)).to contain_exactly(team.id, other_team.id)
    end
  end

  describe 'AccountUser#permissions' do
    let(:account_user) { agent.account_users.find_by(account_id: account.id) }

    it 'keeps the plain agent permissions when nobody supervises anything' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'adds team_supervisor for a supervisor' do
      create(:team_supervisor, team: team, user: agent)

      expect(account_user.reload.permissions).to contain_exactly('agent', 'team_supervisor')
    end

    it 'adds team_supervisor for an administrator that supervises a team' do
      admin = create(:user, account: account, role: :administrator)
      create(:team_supervisor, team: team, user: admin)

      expect(admin.account_users.find_by(account_id: account.id).permissions).to contain_exactly('administrator', 'team_supervisor')
    end
  end
end
