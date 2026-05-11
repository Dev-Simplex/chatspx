# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::OutboundSpecialMessageService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) do
    inbox = channel.inbox
    inbox.update!(waha_session_name: 'default')
    inbox
  end
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566999998888@c.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  let(:waha_api) { instance_double(Waha::ApiService) }

  before do
    allow(Waha::ApiService).to receive(:new).and_return(waha_api)
    allow(waha_api).to receive(:check_contact_exists).and_return(
      'chatId' => '5566999998888@c.us', 'numberExists' => true
    )
    allow(waha_api).to receive(:send_location).and_return('id' => 'loc-1')
    allow(waha_api).to receive(:send_contact_vcard).and_return('id' => 'vc-1')
    allow(waha_api).to receive(:send_text_with_vcard).and_return('id' => 'tv-1')
  end

  describe '#perform' do
    context 'with a location attachment' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -15.6,
          coordinates_long: -56.1,
          fallback_title: 'Cuiabá'
        )
        msg.reload
      end

      it 'dispatches via Waha::ApiService#send_location and returns true' do
        result = described_class.new(message).perform

        expect(waha_api).to have_received(:send_location).with(
          session: 'default',
          chat_id: '5566999998888@c.us',
          latitude: -15.6,
          longitude: -56.1
        )
        expect(result).to be(true)
      end

      it 'marks the message as sent' do
        described_class.new(message).perform
        expect(message.reload.status).to eq('sent')
      end
    end

    context 'with a saved contact attachment (has phone, source != manual)' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox,
                               additional_attributes: { 'contact' => { 'name' => 'Maria', 'phone' => '+5511988887777', 'source' => 'agent' } })
        msg.attachments.create!(
          account_id: account.id,
          file_type: :contact,
          fallback_title: '+5511988887777',
          meta: { 'firstName' => 'Maria' }
        )
        msg.reload
      end

      it 'dispatches via Waha::ApiService#send_text_with_vcard (sendContactVcard quebra na GoWS PLUS)' do
        described_class.new(message).perform

        expect(waha_api).to have_received(:send_text_with_vcard).with(
          session: 'default',
          chat_id: '5566999998888@c.us',
          name: 'Maria',
          phone: '+5511988887777'
        )
      end
    end

    context 'with a manual contact attachment (free dial — source == manual)' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox,
                               additional_attributes: { 'contact' => { 'name' => 'João', 'phone' => '+5511977776666', 'source' => 'manual' } })
        msg.attachments.create!(
          account_id: account.id,
          file_type: :contact,
          fallback_title: '+5511977776666'
        )
        msg.reload
      end

      it 'dispatches via Waha::ApiService#send_text_with_vcard (inline vCard via /api/sendText)' do
        described_class.new(message).perform

        expect(waha_api).to have_received(:send_text_with_vcard).with(
          session: 'default',
          chat_id: '5566999998888@c.us',
          name: 'João',
          phone: '+5511977776666'
        )
      end
    end

    context 'when not applicable' do
      it 'returns false for incoming messages' do
        msg = create(:message, conversation: conversation, message_type: :incoming, inbox: inbox)
        msg.attachments.create!(account_id: account.id, file_type: :location,
                                coordinates_lat: -15.6, coordinates_long: -56.1)

        expect(described_class.new(msg.reload).perform).to be(false)
        expect(waha_api).not_to have_received(:send_location)
      end

      it 'returns false when waha_session_name is blank' do
        inbox.update!(waha_session_name: nil)
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(account_id: account.id, file_type: :location,
                                coordinates_lat: -15.6, coordinates_long: -56.1)

        expect(described_class.new(msg.reload).perform).to be(false)
      end

      it 'returns false for non-location/contact attachments' do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        attachment = msg.attachments.new(account_id: account.id, file_type: :image)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        attachment.save!

        expect(described_class.new(msg.reload).perform).to be(false)
      end

      it 'returns false when there is no attachment' do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        expect(described_class.new(msg.reload).perform).to be(false)
      end
    end

    context 'when contact_inbox.source_id is a UUID (Channel::Api generic), falls back to contact.phone_number' do
      let(:contact) { create(:contact, account: account, phone_number: '+5566996822686') }
      let(:contact_inbox) do
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'a8182041-4dec-4942-bb8e-5b957a05aa8a')
      end
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -11.8604,
          coordinates_long: -55.5095,
          fallback_title: 'Sinop-MT'
        )
        msg.reload
      end

      before do
        allow(waha_api).to receive(:check_contact_exists).with(
          session_name: 'default', phone: '5566996822686'
        ).and_return('chatId' => '556696822686@c.us', 'numberExists' => true)
      end

      it 'resolves chat_id from contact.phone_number and dispatches send_location with canonical chatId' do
        described_class.new(message).perform

        expect(waha_api).to have_received(:check_contact_exists).with(
          session_name: 'default', phone: '5566996822686'
        )
        expect(waha_api).to have_received(:send_location).with(
          session: 'default',
          chat_id: '556696822686@c.us',
          latitude: -11.8604,
          longitude: -55.5095
        )
      end
    end

    context 'when the WhatsApp number is not registered' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -15.6,
          coordinates_long: -56.1
        )
        msg.reload
      end

      before do
        allow(waha_api).to receive(:check_contact_exists).and_return(
          'numberExists' => false, 'chatId' => nil
        )
      end

      it 'does not dispatch and marks the message as failed' do
        result = described_class.new(message).perform

        expect(waha_api).not_to have_received(:send_location)
        expect(waha_api).not_to have_received(:send_text_with_vcard)
        expect(result).to be(true)
        expect(message.reload.status).to eq('failed')
      end
    end

    context 'when the WAHA send returns an external id' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -15.6,
          coordinates_long: -56.1
        )
        msg.reload
      end

      before do
        allow(waha_api).to receive(:send_location).and_return('id' => 'wahaid-123')
      end

      it 'preserves the WAHA id on source_id' do
        described_class.new(message).perform
        expect(message.reload.source_id).to eq('wahaid-123')
      end
    end

    context 'when message.source_id is already set (idempotency guard)' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox,
                               source_id: 'wahaid-existing')
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -15.6,
          coordinates_long: -56.1
        )
        msg.reload
      end

      it 'is idempotent: returns false and does not re-dispatch via WAHA' do
        result = described_class.new(message).perform

        expect(result).to be(false)
        expect(waha_api).not_to have_received(:send_location)
        expect(waha_api).not_to have_received(:send_text_with_vcard)
      end
    end

    context 'when the WAHA call raises' do
      let(:message) do
        msg = create(:message, conversation: conversation, message_type: :outgoing, inbox: inbox)
        msg.attachments.create!(
          account_id: account.id,
          file_type: :location,
          coordinates_lat: -15.6,
          coordinates_long: -56.1
        )
        msg.reload
      end

      before do
        allow(waha_api).to receive(:send_location).and_raise(Waha::ApiService::Error.new('boom'))
      end

      it 'marks the message as failed and returns true to suppress webhook fallback' do
        result = described_class.new(message).perform

        expect(result).to be(true)
        expect(message.reload.status).to eq('failed')
        expect(message.reload.external_error).to eq('boom')
      end
    end
  end
end
