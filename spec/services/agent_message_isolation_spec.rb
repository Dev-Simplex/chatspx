# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentMessageIsolation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }

  describe '.viewer_restriction_id' do
    it 'returns the user id for a non-admin agent' do
      expect(described_class.viewer_restriction_id(agent, account)).to eq(agent.id)
    end

    it 'returns nil for an administrator' do
      expect(described_class.viewer_restriction_id(admin, account)).to be_nil
    end

    it 'returns nil when there is no user (widget/public/job context)' do
      expect(described_class.viewer_restriction_id(nil, account)).to be_nil
    end

    it 'accepts an account id instead of an account object' do
      expect(described_class.viewer_restriction_id(agent, account.id)).to eq(agent.id)
    end

    it 'returns nil when the account is blank' do
      expect(described_class.viewer_restriction_id(agent, nil)).to be_nil
    end
  end

  describe '.restriction_id_for_inbox' do
    let!(:team) { create(:team, account: account) }
    let!(:other_team) { create(:team, account: account) }

    it 'returns nil when the inbox does not have isolation enabled' do
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to be_nil
    end

    it 'returns the agent id when isolation is enabled' do
      inbox.update!(agent_message_isolation: true)
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to eq(agent.id)
    end

    it 'returns nil for an admin even with isolation enabled' do
      inbox.update!(agent_message_isolation: true)
      expect(described_class.restriction_id_for_inbox(inbox, admin, account, team.id)).to be_nil
    end

    # ESCOPO POR TIME
    it 'restricts any team when the team list is empty (retrocompat)' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, other_team.id)).to eq(agent.id)
    end

    it 'restricts a team inside the chosen list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to eq(agent.id)
    end

    it 'does not restrict a team outside the chosen list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, other_team.id)).to be_nil
    end

    it 'does not restrict a conversation without a team' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, nil)).to be_nil
    end

    it 'does not restrict a conversation without a team even with an empty list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, nil)).to be_nil
    end
  end

  describe '.filter_messages' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:public_msg) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
    end
    let!(:mine) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent)
    end
    let!(:other) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       sender: create(:user, account: account, role: :agent))
    end

    it 'returns the same scope untouched when restriction id is nil' do
      scope = conversation.messages
      expect(described_class.filter_messages(scope, nil)).to be(scope)
    end

    it 'keeps public (agent_id NULL) and own messages, drops other agents messages' do
      ids = described_class.filter_messages(conversation.messages, agent.id).map(&:id)
      expect(ids).to include(public_msg.id, mine.id)
      expect(ids).not_to include(other.id)
    end
  end
end
