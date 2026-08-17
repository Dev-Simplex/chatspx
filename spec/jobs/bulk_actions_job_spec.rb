require 'rails_helper'

RSpec.describe BulkActionsJob do
  subject(:job) { described_class.perform_later(account_id: account.id, params: params, user_id: agent.id) }

  let(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation_1) { create(:conversation, account_id: account.id, status: :open) }
  let!(:conversation_2) { create(:conversation, account_id: account.id, status: :open) }
  let!(:conversation_3) { create(:conversation, account_id: account.id, status: :open) }
  let(:conversation_ids) { [conversation_1.display_id, conversation_2.display_id, conversation_3.display_id] }
  let(:params) { { type: 'Conversation', fields: { status: 'snoozed' }, ids: conversation_ids } }

  before do
    [conversation_1, conversation_2, conversation_3].each do |conversation|
      create(:inbox_member, inbox: conversation.inbox, user: agent)
    end
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account_id: account.id, params: params, user_id: agent.id)
      .on_queue('medium')
  end

  context 'when job is triggered' do
    let(:bulk_action_job) { double }

    before do
      allow(bulk_action_job).to receive(:perform)
    end

    it 'bulk updates the status' do
      params = {
        type: 'Conversation',
        fields: { status: 'snoozed', assignee_id: agent.id },
        ids: conversation_ids
      }

      expect(conversation_1.status).to eq('open')

      described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

      expect(conversation_1.reload.status).to eq('snoozed')
      expect(conversation_2.reload.status).to eq('snoozed')
      expect(conversation_3.reload.status).to eq('snoozed')
    end

    it 'bulk updates the assignee_id' do
      params = {
        type: 'Conversation',
        fields: { status: 'snoozed', assignee_id: agent.id },
        ids: conversation_ids
      }

      expect(conversation_1.assignee_id).to be_nil

      described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

      expect(conversation_1.reload.assignee_id).to eq(agent.id)
      expect(conversation_2.reload.assignee_id).to eq(agent.id)
      expect(conversation_3.reload.assignee_id).to eq(agent.id)
    end

    it 'bulk updates the snoozed_until' do
      params = {
        type: 'Conversation',
        fields: { status: 'snoozed', snoozed_until: Time.zone.now },
        ids: conversation_ids
      }

      expect(conversation_1.snoozed_until).to be_nil

      described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

      expect(conversation_1.reload.snoozed_until).to be_present
      expect(conversation_2.reload.snoozed_until).to be_present
      expect(conversation_3.reload.snoozed_until).to be_present
    end

    it 'skips conversations whose inbox the agent does not belong to' do
      forbidden_conversation = create(:conversation, account_id: account.id, status: :open)
      params = {
        type: 'Conversation',
        fields: { status: 'resolved' },
        ids: [conversation_1.display_id, forbidden_conversation.display_id]
      }

      described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

      expect(conversation_1.reload.status).to eq('resolved')
      expect(forbidden_conversation.reload.status).to eq('open')
    end

    context 'when the resolve assignment gate is enabled' do
      let(:team) { create(:team, account: account) }

      before do
        account.update!(settings: { resolve_assignment_gate: true })
        create(:team_member, user: agent, team: team)
        [conversation_1, conversation_2, conversation_3].each { |c| c.update!(team: team) }
      end

      it 'resolves only the conversations assigned to the acting user' do
        conversation_1.update!(assignee: agent)
        params = {
          type: 'Conversation',
          fields: { status: 'resolved' },
          ids: [conversation_1, conversation_2, conversation_3].map(&:display_id)
        }

        described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

        expect(conversation_1.reload.status).to eq('resolved')
        expect(conversation_2.reload.status).to eq('open')
        expect(conversation_3.reload.status).to eq('open')
      end

      it 'resolves all when the acting user is self-assigned in the same payload' do
        params = {
          type: 'Conversation',
          fields: { status: 'resolved', assignee_id: agent.id },
          ids: [conversation_1, conversation_2, conversation_3].map(&:display_id)
        }

        described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

        expect(conversation_1.reload.status).to eq('resolved')
        expect(conversation_2.reload.status).to eq('resolved')
        expect(conversation_3.reload.status).to eq('resolved')
      end
    end

    context 'when agent conversation isolation is enabled on the inbox' do
      let!(:owner) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation_1.inbox, user: owner)
        conversation_1.inbox.update!(agent_conversation_isolation: true)
        conversation_1.update!(assignee: owner)
      end

      it 'skips assignee/status/label changes on a colleague-owned isolated conversation' do
        params = {
          type: 'Conversation',
          fields: { status: 'snoozed', assignee_id: agent.id },
          labels: { add: ['roubada'] },
          ids: [conversation_1.display_id]
        }

        described_class.perform_now(account_id: account.id, params: params, user_id: agent.id)

        conversation_1.reload
        expect(conversation_1.assignee_id).to eq(owner.id)
        expect(conversation_1.status).to eq('open')
        expect(conversation_1.label_list).not_to include('roubada')
      end

      it 'still lets the owner act on their own isolated conversation' do
        params = { type: 'Conversation', fields: { status: 'snoozed' }, ids: [conversation_1.display_id] }
        described_class.perform_now(account_id: account.id, params: params, user_id: owner.id)
        expect(conversation_1.reload.status).to eq('snoozed')
      end

      it 'still lets an administrator act' do
        admin = create(:user, account: account, role: :administrator)
        params = { type: 'Conversation', fields: { status: 'snoozed' }, ids: [conversation_1.display_id] }
        described_class.perform_now(account_id: account.id, params: params, user_id: admin.id)
        expect(conversation_1.reload.status).to eq('snoozed')
      end
    end
  end
end
