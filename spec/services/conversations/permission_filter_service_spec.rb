require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user has teams' do
      let(:team) { create(:team, account: account) }
      let(:another_team) { create(:team, account: account) }
      let(:agent_with_team) { create(:user, account: account, role: :agent) }
      let!(:conversation_with_team) { create(:conversation, account: account, inbox: inbox, team: team) }
      let!(:conversation_with_another_team) { create(:conversation, account: account, inbox: inbox, team: another_team) }
      let!(:conversation_without_team) { create(:conversation, account: account, inbox: inbox, team: nil) }

      before do
        create(:team_member, team: team, user: agent_with_team)
        create(:inbox_member, user: agent_with_team, inbox: inbox)
      end

      it 'returns only conversations from user teams or without team' do
        result = described_class.new(
          account.conversations,
          agent_with_team,
          account
        ).perform

        expect(result).to include(conversation_with_team)
        expect(result).to include(conversation_without_team)
        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result).not_to include(conversation_with_another_team)
      end
    end

    context 'when user has no teams' do
      let(:agent_without_team) { create(:user, account: account, role: :agent) }
      let!(:conversation_with_team) { create(:conversation, account: account, inbox: inbox, team: create(:team, account: account)) }
      let!(:conversation_without_team) { create(:conversation, account: account, inbox: inbox, team: nil) }

      before { create(:inbox_member, user: agent_without_team, inbox: inbox) }

      it 'returns all conversations from accessible inboxes' do
        result = described_class.new(
          account.conversations,
          agent_without_team,
          account
        ).perform

        expect(result).to include(conversation_with_team)
        expect(result).to include(conversation_without_team)
        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
      end
    end
  end
end
