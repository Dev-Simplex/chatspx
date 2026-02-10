require 'rails_helper'

RSpec.describe Conversations::ListPreloader do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: nil) }

    it 'preloads last messages, last non-activity messages, and caps unread counts' do
      create_list(:message, 12, account: account, conversation: conversation, message_type: :incoming)
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      last_non_activity = create(:message, account: account, conversation: conversation, message_type: :outgoing)
      last_message = create(:message, account: account, conversation: conversation, message_type: :activity)

      result = described_class.new([conversation], account_id: account.id).perform

      expect(result[:last_messages_by_conversation_id][conversation.id]).to eq(last_message)
      expect(result[:last_non_activity_messages_by_conversation_id][conversation.id]).to eq(last_non_activity)
      expect(result[:unread_counts_by_conversation_id][conversation.id]).to eq(10)
    end
  end
end
