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
end
