# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentConversationIsolation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:owner) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }

  describe '.hidden_from?' do
    context 'when the inbox is NOT isolated' do
      it 'never hides, even a colleague conversation' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end
    end

    context 'when the inbox IS isolated' do
      before { inbox.update!(agent_conversation_isolation: true) }

      it 'hides a colleague-owned conversation from a non-owner agent' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(true)
      end

      it 'does not hide my own conversation' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: agent)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'does not hide an unassigned conversation (queue/AI accessible to assume)' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: nil)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'never hides from an administrator' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: owner)
        expect(described_class.hidden_from?(conv, admin, account)).to be(false)
      end

      it 'never hides when there is no user (jobs/widget/public context)' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: owner)
        expect(described_class.hidden_from?(conv, nil, account)).to be(false)
      end

      it 'derives the account from the conversation when not passed' do
        conv = create(:conversation, account: account, inbox: inbox, assignee: owner)
        expect(described_class.hidden_from?(conv, agent)).to be(true)
      end
    end
  end

  describe '.exclude_hidden' do
    let(:relation) { account.conversations.joins(:inbox) }

    context 'when the inbox IS isolated' do
      before { inbox.update!(agent_conversation_isolation: true) }

      let!(:mine) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
      let!(:foreign) { create(:conversation, account: account, inbox: inbox, assignee: owner) }
      let!(:unassigned) { create(:conversation, account: account, inbox: inbox, assignee: nil) }

      it 'removes a colleague-owned conversation for a non-owner agent' do
        result = described_class.exclude_hidden(relation, agent, account)
        expect(result).to include(mine, unassigned)
        expect(result).not_to include(foreign)
      end

      it 'keeps everything for an administrator' do
        result = described_class.exclude_hidden(relation, admin, account)
        expect(result).to include(mine, foreign, unassigned)
      end

      it 'returns the relation untouched when there is no user' do
        expect(described_class.exclude_hidden(relation, nil, account)).to eq(relation)
      end
    end

    context 'when the inbox is NOT isolated' do
      let!(:foreign) { create(:conversation, account: account, inbox: inbox, assignee: owner) }

      it 'keeps a colleague conversation' do
        expect(described_class.exclude_hidden(relation, agent, account)).to include(foreign)
      end
    end
  end
end
