require 'rails_helper'

describe MessageFinder do
  subject(:message_finder) { described_class.new(conversation, params) }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, email: nil) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: user, contact: contact)
  end

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    # this outgoing message creates 2 additional messages because of the email hook execution service
    create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation)
  end

  describe '#perform' do
    context 'with filter_internal_messages false' do
      let(:params) { { filter_internal_messages: false } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with filter_internal_messages true' do
      let(:params) { { filter_internal_messages: true } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 4
      end
    end

    context 'with before attribute' do
      let!(:outgoing) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
      let(:params) { { before: outgoing.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with before attribute and custom limit' do
      let(:params) { { before: conversation.messages.maximum(:id) + 1, limit: 4 } }

      before do
        create_list(:message, 10, account: account, inbox: inbox, conversation: conversation)
      end

      it 'returns only the requested page size and tracks has_more' do
        result = message_finder.perform
        expect(result.count).to eq 4
        expect(message_finder.has_more).to be(true)
        expect(result.map(&:id)).to eq(result.map(&:id).sort)
      end
    end

    context 'with before attribute and limit above max cap' do
      let(:params) { { before: conversation.messages.maximum(:id) + 1, limit: 250 } }

      before do
        create_list(:message, 140, account: account, inbox: inbox, conversation: conversation)
      end

      it 'caps the page size to 100 records' do
        result = message_finder.perform
        expect(result.count).to eq 100
      end
    end

    context 'with after attribute' do
      let(:params) { { after: conversation.messages.first.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.first.id).to be conversation.messages.second.id
        expect(result.last.message_type).to eq 'outgoing'
      end
    end

    context 'with after and before attribute' do
      let(:params) do
        {
          after: conversation.messages.first.id,
          before: conversation.messages.last.id
        }
      end

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.last.id).to be conversation.messages[-2].id
      end
    end

    context 'when before points to the end of history' do
      let(:oldest_message_id) { conversation.messages.minimum(:id) }
      let(:params) { { before: oldest_message_id + 1, limit: 20 } }

      it 'marks has_more as false for the last page' do
        result = message_finder.perform
        expect(result.count).to eq 1
        expect(message_finder.has_more).to be(false)
      end
    end
  end

  describe '#perform with agent_message_isolation' do
    subject(:finder) { described_class.new(iso_conversation, { filter_internal_messages: false }) }

    let!(:account) { create(:account) }
    let!(:agent_a) { create(:user, account: account, role: :agent) }
    let!(:agent_b) { create(:user, account: account, role: :agent) }
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let!(:inbox) { create(:inbox, account: account) }
    let!(:team) { create(:team, account: account) }
    let!(:other_team) { create(:team, account: account) }
    # COM time de proposito: o isolamento e escopado pelo time da CONVERSA, e conversa
    # sem time nunca e isolada (Inbox#isolation_applies_to_team?).
    let!(:iso_conversation) { create(:conversation, account: account, inbox: inbox, team: team) }

    let!(:incoming) { create(:message, message_type: :incoming, conversation: iso_conversation, account: account, inbox: inbox) }
    let!(:from_a) do
      create(:message, message_type: :outgoing, sender: agent_a, conversation: iso_conversation, account: account, inbox: inbox)
    end
    let!(:from_b) do
      create(:message, message_type: :outgoing, sender: agent_b, conversation: iso_conversation, account: account, inbox: inbox)
    end

    after { Current.user = nil }

    context 'when isolation is enabled' do
      before { inbox.update!(agent_message_isolation: true) }

      it 'shows an agent their own and public messages but hides other agents messages' do
        Current.user = agent_a
        ids = finder.perform.map(&:id)
        expect(ids).to include(incoming.id, from_a.id)
        expect(ids).not_to include(from_b.id)
      end

      it 'lets an account administrator see every message' do
        Current.user = admin
        ids = finder.perform.map(&:id)
        expect(ids).to include(incoming.id, from_a.id, from_b.id)
      end

      it 'applies no filter when there is no Current.user (widget/public listing)' do
        Current.user = nil
        ids = finder.perform.map(&:id)
        expect(ids).to include(incoming.id, from_a.id, from_b.id)
      end
    end

    context 'when isolation is disabled' do
      it 'shows all messages even to a non-admin agent' do
        Current.user = agent_a
        ids = finder.perform.map(&:id)
        expect(ids).to include(incoming.id, from_a.id, from_b.id)
      end
    end

    # ESCOPO POR TIME: a flag liga a regra na caixa, a lista diz em QUAIS times ela vale.
    context 'when isolation is scoped to teams' do
      before do
        inbox.update!(agent_message_isolation: true)
        Current.user = agent_a
      end

      it 'hides the colleague bubble when the team list is empty (retrocompat)' do
        inbox.update!(agent_message_isolation_team_ids: [])
        expect(finder.perform.map(&:id)).not_to include(from_b.id)
      end

      it 'hides the colleague bubble when the conversation team is in the list' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        expect(finder.perform.map(&:id)).not_to include(from_b.id)
      end

      it 'shows every bubble when the conversation team is NOT in the list' do
        inbox.update!(agent_message_isolation_team_ids: [other_team.id])
        expect(finder.perform.map(&:id)).to include(incoming.id, from_a.id, from_b.id)
      end

      it 'shows every bubble on a conversation without a team' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        iso_conversation.update!(team: nil)
        expect(finder.perform.map(&:id)).to include(incoming.id, from_a.id, from_b.id)
      end

      it 'shows every bubble to an administrator whatever the list' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        Current.user = admin
        expect(finder.perform.map(&:id)).to include(incoming.id, from_a.id, from_b.id)
      end
    end
  end
end
