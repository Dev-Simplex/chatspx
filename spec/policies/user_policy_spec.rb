# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserPolicy, type: :policy do
  subject(:user_policy) { described_class }

  let(:account) { create(:account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:user) { create(:user, account: account) }
  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :create?, :update?, :destroy? do
    context 'when administrator' do
      it { expect(user_policy).to permit(administrator_context, user) }
    end

    context 'when agent' do
      it { expect(user_policy).not_to permit(agent_context, user) }
    end
  end

  # T1: o supervisor de time entra no update? (renomear os agentes dos times dele), mas
  # continua fora do create?/destroy? — convidar e excluir agente segue exclusivo de admin.
  context 'when the agent supervises a team' do
    let(:supervisor_context) do
      create(:team_supervisor, team: create(:team, account: account), user: agent)
      { user: agent, account: account, account_user: account.account_users.find_by(user_id: agent.id) }
    end

    permissions :update? do
      it { expect(user_policy).to permit(supervisor_context, user) }
    end

    permissions :create?, :destroy? do
      it { expect(user_policy).not_to permit(supervisor_context, user) }
    end
  end

  permissions :index? do
    context 'when administrator' do
      it { expect(user_policy).to permit(administrator_context, user) }
    end

    context 'when agent' do
      it { expect(user_policy).to permit(agent_context, user) }
    end
  end
end
