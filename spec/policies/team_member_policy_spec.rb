# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamMemberPolicy, type: :policy do
  subject(:team_member_policy) { described_class }

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: account.account_users.find_by(user_id: administrator.id) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: account.account_users.find_by(user_id: agent.id) }
  end
  # T1: a policy recebe a CLASSE TeamMember, então ela só sabe "é supervisor de ALGUM
  # time?". Qual time e quem pode entrar é decidido no TeamMembersController — as
  # recusas de time não supervisionado / agente fora do pool estão cobertas lá.
  let(:supervisor_context) do
    create(:team_supervisor, team: team, user: agent)
    agent_context
  end

  permissions :create?, :update?, :destroy? do
    context 'when administrator' do
      it { expect(team_member_policy).to permit(administrator_context, TeamMember) }
    end

    context 'when plain agent' do
      it { expect(team_member_policy).not_to permit(agent_context, TeamMember) }
    end

    context 'when the agent supervises a team' do
      it { expect(team_member_policy).to permit(supervisor_context, TeamMember) }
    end

    context 'when the agent supervises a team of ANOTHER account' do
      it 'stays out' do
        other_account = create(:account)
        create(:account_user, user: agent, account: other_account, role: :agent)
        create(:team_supervisor, team: create(:team, account: other_account), user: agent)

        expect(team_member_policy).not_to permit(agent_context, TeamMember)
      end
    end
  end
end
