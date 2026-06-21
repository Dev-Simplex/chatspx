require 'rails_helper'

describe Conversations::ToggleStatusService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    # The assignee must belong to the conversation's team, otherwise the model
    # (AssignmentHandler#validate_current_assignee_team) clears the assignee on save.
    create(:team_member, user: agent, team: team)
  end

  describe '#perform with the resolve assignment gate' do
    context 'when the gate is enabled' do
      before { account.update!(settings: { resolve_assignment_gate: true }) }

      let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: 'open') }

      it 'allows the assignee to resolve' do
        described_class.new(conversation: conversation, params: { status: 'resolved' }, user: agent).perform
        expect(conversation.reload.status).to eq('resolved')
      end

      it 'blocks a non-assignee agent from resolving' do
        expect do
          described_class.new(conversation: conversation, params: { status: 'resolved' }, user: other_agent).perform
        end.to raise_error(Conversations::ToggleStatusService::ResolveAssignmentRequiredError)
        expect(conversation.reload.status).to eq('open')
      end

      it 'blocks an administrator who is not the assignee (no exception)' do
        expect do
          described_class.new(conversation: conversation, params: { status: 'resolved' }, user: administrator).perform
        end.to raise_error(Conversations::ToggleStatusService::ResolveAssignmentRequiredError)
      end

      it 'exposes the current assignee and team in the error metadata' do
        described_class.new(conversation: conversation, params: { status: 'resolved' }, user: other_agent).perform
      rescue Conversations::ToggleStatusService::ResolveAssignmentRequiredError => e
        expect(e.meta).to include(current_assignee_id: agent.id, team_id: team.id)
      end

      it 'blocks a non-assignee from resolving via the param-less toggle' do
        expect(conversation.status).to eq('open')
        expect do
          described_class.new(conversation: conversation, params: {}, user: other_agent).perform
        end.to raise_error(Conversations::ToggleStatusService::ResolveAssignmentRequiredError)
        expect(conversation.reload.status).to eq('open')
      end

      it 'lets the assignee resolve via the param-less toggle' do
        described_class.new(conversation: conversation, params: {}, user: agent).perform
        expect(conversation.reload.status).to eq('resolved')
      end

      it 'does not block re-opening a resolved conversation via toggle' do
        conversation.update!(status: 'resolved')
        expect do
          described_class.new(conversation: conversation, params: {}, user: other_agent).perform
        end.not_to raise_error
        expect(conversation.reload.status).to eq('open')
      end

      it 'does not block non-resolve transitions' do
        expect do
          described_class.new(conversation: conversation, params: { status: 'snoozed', snoozed_until: 2.days.from_now.to_i },
                              user: other_agent).perform
        end.not_to raise_error
        expect(conversation.reload.status).to eq('snoozed')
      end

      it 'bypasses the gate for an agent bot' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect do
          described_class.new(conversation: conversation, params: { status: 'resolved' }, user: agent_bot).perform
        end.not_to raise_error
        expect(conversation.reload.status).to eq('resolved')
      end

      it 'still requires a team even for the assignee' do
        conversation.update!(team: nil)
        expect do
          described_class.new(conversation: conversation, params: { status: 'resolved' }, user: agent).perform
        end.to raise_error(Conversations::ToggleStatusService::TeamRequiredError)
      end
    end

    context 'when the gate is disabled (classic mode)' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: 'open') }

      it 'lets a non-assignee resolve as before' do
        expect do
          described_class.new(conversation: conversation, params: { status: 'resolved' }, user: other_agent).perform
        end.not_to raise_error
        expect(conversation.reload.status).to eq('resolved')
      end
    end
  end
end
