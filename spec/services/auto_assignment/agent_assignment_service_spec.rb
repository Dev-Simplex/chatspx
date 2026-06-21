require 'rails_helper'

RSpec.describe AutoAssignment::AgentAssignmentService do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:inbox_members) { create_list(:inbox_member, 5, inbox: inbox) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:online_users) do
    {
      inbox_members[0].user_id.to_s => 'busy',
      inbox_members[1].user_id.to_s => 'busy',
      inbox_members[2].user_id.to_s => 'busy',
      inbox_members[3].user_id.to_s => 'online',
      inbox_members[4].user_id.to_s => 'online'
    }
  end

  before do
    inbox_members.each { |inbox_member| create(:account_user, account: account, user: inbox_member.user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(online_users)
  end

  describe '#perform' do
    it 'will assign an online agent to the conversation' do
      expect(conversation.reload.assignee).to be_nil
      described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).perform
      expect(conversation.reload.assignee).not_to be_nil
    end

    context 'when the conversation is owned by a captain mirror bot' do
      let(:assistant) { create(:captain_assistant, account: account) }

      before do
        conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)
      end

      it 'never steals the conversation from the AI' do
        described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).perform

        expect(conversation.reload.assignee).to be_nil
        expect(conversation.reload.assignee_agent_bot).to eq(assistant.mirror_agent_bot)
      end
    end

    # Trava estrutural C8: o round-robin só resolve ids para inbox_members (Users) —
    # um espelho captain "infiltrado" em allowed_agent_ids nunca pode ser atribuído.
    context 'when a captain mirror id is infiltrated in the allowed agent ids' do
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:mirror) { assistant.mirror_agent_bot }

      it 'does not assign the mirror bot' do
        allow(OnlineStatusTracker).to receive(:get_available_users)
          .and_return(online_users.merge(mirror.id.to_s => 'online'))

        described_class.new(conversation: conversation, allowed_agent_ids: [mirror.id.to_s]).perform

        conversation.reload
        expect(conversation.assignee).to be_nil
        expect(conversation.assignee_agent_bot).to be_nil
      end
    end
  end

  describe '#find_assignee' do
    it 'will return an online agent from the allowed agent ids in roud robin' do
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[3].user)
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[4].user)
    end
  end
end
