require 'rails_helper'

RSpec.describe Messages::DeleteContentService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) do
    create(:inbox, channel: api_channel, account: account, waha_session_name: 'TestSession')
  end
  let(:contact) do
    create(:contact, account: account,
                     custom_attributes: { 'waha_whatsapp_chat_id' => '5566999999999@c.us' })
  end
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566999999999@c.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:waha_api) { instance_double(Waha::ApiService) }

  let(:original_content) { 'Hello world' }

  let(:message) do
    create(:message,
           account: account,
           inbox: inbox,
           conversation: conversation,
           sender: user,
           message_type: :outgoing,
           content: original_content,
           content_type: :text)
  end

  before do
    Current.user = user
    allow(Waha::ApiService).to receive(:new).and_return(waha_api)
    allow(waha_api).to receive(:delete_message).and_return({})
  end

  after { Current.user = nil }

  describe '#perform' do
    context 'when WAHA propagation is eligible and source_id is present' do
      before { message.update!(source_id: 'true_5566999999999@c.us_ABC123') }

      it 'skips the WAHA lookup and deletes directly on WAHA' do
        expect(waha_api).not_to receive(:get_messages)
        expect(waha_api).to receive(:delete_message).with(
          'TestSession', '5566999999999@c.us', 'true_5566999999999@c.us_ABC123'
        )

        described_class.new(message).perform
      end

      it 'persists the deleted metadata and preserves the original content' do
        described_class.new(message).perform

        message.reload
        expect(message.content).to eq I18n.t('conversations.messages.deleted')
        expect(message.content_attributes['previous_content']).to eq(original_content)
        expect(message.content_attributes['deleted']).to be true
        expect(message.content_attributes['deleted_at']).to be_present
        expect(message.content_attributes['deleted_by']).to include('id' => user.id, 'name' => user.name)
      end

      it 'destroys attachments' do
        attachment = message.attachments.new(account_id: account.id, file_type: :image)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        message.save!

        described_class.new(message).perform

        expect(message.reload.attachments).to be_empty
      end
    end

    context 'when source_id is missing and the WAHA lookup resolves a match' do
      before do
        allow(waha_api).to receive(:get_messages).and_return(
          [{ 'id' => 'true_5566999999999@c.us_LOOKUP_ID', 'fromMe' => true,
             'body' => original_content, 'timestamp' => message.created_at.to_i }]
        )
      end

      it 'deletes on WAHA and persists the resolved source_id' do
        expect(waha_api).to receive(:delete_message).with(
          'TestSession', '5566999999999@c.us', 'true_5566999999999@c.us_LOOKUP_ID'
        )

        described_class.new(message).perform
        expect(message.reload.source_id).to eq('true_5566999999999@c.us_LOOKUP_ID')
      end
    end

    context 'when the message was already deleted' do
      before { message.update!(content_attributes: { 'deleted' => true }) }

      it 'raises ArgumentError' do
        expect { described_class.new(message).perform }.to raise_error(ArgumentError, /already been deleted/)
      end
    end

    context 'when the acting agent is not the sender (WAHA inbox)' do
      let(:other_user) { create(:user, account: account) }

      before { Current.user = other_user }

      it 'still soft-deletes locally but does NOT propagate to WAHA' do
        expect(waha_api).not_to receive(:delete_message)

        described_class.new(message).perform

        message.reload
        expect(message.content_attributes['deleted']).to be true
        expect(message.content_attributes['previous_content']).to eq(original_content)
        expect(message.content_attributes['deleted_by']).to include('id' => other_user.id)
      end
    end

    context 'when the inbox is not a WAHA inbox' do
      let(:inbox) { create(:inbox, channel: api_channel, account: account, waha_session_name: nil) }

      before { message.update!(source_id: 'should_not_be_used') }

      it 'soft-deletes locally without touching WAHA' do
        expect(waha_api).not_to receive(:delete_message)

        described_class.new(message).perform

        expect(message.reload.content_attributes['deleted']).to be true
      end
    end

    context 'when the WAHA message id cannot be resolved' do
      before do
        allow(waha_api).to receive(:get_messages).and_return([])
      end

      it 'soft-deletes locally only and does not raise' do
        expect(waha_api).not_to receive(:delete_message)

        expect { described_class.new(message).perform }.not_to raise_error
        expect(message.reload.content_attributes['deleted']).to be true
      end
    end

    context 'when WAHA returns a hard API error' do
      before do
        message.update!(source_id: 'true_5566999999999@c.us_ABC123')
        allow(waha_api).to receive(:delete_message).and_raise(Waha::ApiService::Error.new('boom'))
      end

      it 'raises ArgumentError and does not soft-delete locally' do
        expect { described_class.new(message).perform }.to raise_error(ArgumentError, /WAHA API error/)
        expect(message.reload.content_attributes['deleted']).to be_falsey
      end
    end
  end
end
