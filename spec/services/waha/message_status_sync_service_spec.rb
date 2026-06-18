# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::MessageStatusSyncService do
  let(:account) { create(:account) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, status: :sent, source_id: 'WAHA1', content: 'oi')
  end
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) do
    i = channel.inbox
    i.update!(waha_session_name: 'default')
    i
  end
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566999998888@c.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:waha_api) { instance_double(Waha::ApiService) }

  before do
    allow(Waha::ApiService).to receive(:new).and_return(waha_api)
  end

  def waha_msg(id:, ack:, body: nil)
    { 'key' => { 'id' => id }, 'id' => id, 'ack' => ack, 'fromMe' => true, 'body' => body, 'timestamp' => Time.current.to_i }
  end

  describe 'WAHA error ack (-1) — positive failure signal' do
    it 'flips a sent message to failed with a friendly external_error' do
      allow(waha_api).to receive(:get_messages).and_return([waha_msg(id: 'WAHA1', ack: -1, body: 'oi')])

      described_class.new(conversation).perform

      message.reload
      expect(message.status).to eq('failed')
      expect(message.external_error).to be_present
    end

    it 'never overrides a delivered message (StatusUpdateService guard)' do
      message.update!(status: :delivered)
      allow(waha_api).to receive(:get_messages).and_return([waha_msg(id: 'WAHA1', ack: -1, body: 'oi')])

      described_class.new(conversation).perform

      expect(message.reload.status).to eq('delivered')
    end
  end

  describe 'positive acks keep working (regression)' do
    it 'maps ack=2 to delivered' do
      allow(waha_api).to receive(:get_messages).and_return([waha_msg(id: 'WAHA1', ack: 2, body: 'oi')])

      described_class.new(conversation).perform

      expect(message.reload.status).to eq('delivered')
    end

    it 'does not change anything when WAHA returns an empty list' do
      allow(waha_api).to receive(:get_messages).and_return([])

      described_class.new(conversation).perform

      expect(message.reload.status).to eq('sent')
    end
  end
end
