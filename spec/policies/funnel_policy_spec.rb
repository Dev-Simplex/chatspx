# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FunnelPolicy, type: :policy do
  let(:account) { create(:account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_without_team) { create(:user, account: account, role: :agent) }

  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }

  # "Geral" — the account default funnel (team_id nil).
  let!(:general_funnel) { Funnel.create!(account: account, name: 'Geral', color: '#94a3b8', position: 0) }
  let!(:team_funnel) { Funnel.create!(account: account, name: 'Time X', color: '#2563eb', team_id: team.id) }
  let!(:other_team_funnel) { Funnel.create!(account: account, name: 'Time Y', color: '#16a34a', team_id: other_team.id) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: account.account_users.find_by(user: administrator) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: account.account_users.find_by(user: agent) }
  end
  let(:agent_without_team_context) do
    { user: agent_without_team, account: account, account_user: account.account_users.find_by(user: agent_without_team) }
  end

  before do
    team.add_members([agent.id])
    # the Scope is team-membership based for everyone, so put the admin on a team
    # to exercise the "team funnels + Geral" case.
    team.add_members([administrator.id])
  end

  describe 'Scope#resolve' do
    def resolved(context)
      Pundit.policy_scope(context, Funnel).to_a
    end

    context 'when administrator' do
      it 'sees their team funnels and the "Geral" default funnel (team_id nil)' do
        result = resolved(administrator_context)
        expect(result).to include(general_funnel, team_funnel)
        expect(result.select { |f| f.team_id.nil? }).to include(general_funnel)
      end
    end

    context 'when agent belonging to a team' do
      it 'sees only their team funnel — not "Geral" nor funnels of teams they are not in' do
        result = resolved(agent_context)
        expect(result).to include(team_funnel)
        expect(result).not_to include(general_funnel, other_team_funnel)
        # every visible funnel belongs to the agent's own team (no "Geral"/nil, no other team)
        expect(result.map(&:team_id).uniq).to contain_exactly(team.id)
      end
    end

    context 'when agent without any team' do
      it 'sees no funnels at all' do
        expect(resolved(agent_without_team_context)).to be_empty
      end
    end
  end

  describe '#show?' do
    context 'with the "Geral" default funnel (team_id nil)' do
      it 'permits the administrator' do
        expect(described_class.new(administrator_context, general_funnel).show?).to be(true)
      end

      it 'forbids the agent' do
        expect(described_class.new(agent_context, general_funnel).show?).to be(false)
      end
    end

    context 'with a team funnel' do
      it 'permits an agent that is a member of the team' do
        expect(described_class.new(agent_context, team_funnel).show?).to be(true)
      end

      it 'forbids an agent that is not a member of the team' do
        expect(described_class.new(agent_context, other_team_funnel).show?).to be(false)
      end
    end
  end

  describe '#stats? (derived from show?)' do
    it 'forbids the agent on the "Geral" funnel' do
      expect(described_class.new(agent_context, general_funnel).stats?).to be(false)
    end

    it 'permits the administrator on the "Geral" funnel' do
      expect(described_class.new(administrator_context, general_funnel).stats?).to be(true)
    end
  end
end
