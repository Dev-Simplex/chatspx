require 'rails_helper'

RSpec.describe Messages::UpdateContentService, type: :service do
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
  let(:new_content) { 'Hello edited' }

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
    allow(waha_api).to receive(:edit_message).and_return(true)
  end

  after { Current.user = nil }

  describe '#perform' do
    context 'when source_id is present' do
      before { message.update!(source_id: 'true_5566999999999@c.us_ABC123') }

      it 'skips the WAHA lookup and edits directly' do
        expect(waha_api).not_to receive(:get_messages)
        expect(waha_api).to receive(:edit_message).with(
          'TestSession', '5566999999999@c.us', 'true_5566999999999@c.us_ABC123', new_content
        )

        described_class.new(message, new_content).perform
      end

      it 'persists previous_content and edited flag' do
        described_class.new(message, new_content).perform

        message.reload
        expect(message.content).to eq(new_content)
        expect(message.content_attributes['previous_content']).to eq(original_content)
        expect(message.content_attributes['edited']).to be true
      end
    end

    context 'when source_id is missing and lookup is required' do
      let(:waha_response) do
        [{
          'id' => 'true_5566999999999@c.us_LOOKUP_ID',
          'fromMe' => true,
          'body' => waha_body,
          'timestamp' => message.created_at.to_i
        }]
      end

      before do
        allow(waha_api).to receive(:get_messages).and_return(waha_response)
      end

      context 'with exact body match' do
        let(:waha_body) { original_content }

        it 'finds the WAHA message' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
          expect(message.reload.source_id).to eq('true_5566999999999@c.us_LOOKUP_ID')
        end
      end

      context 'with agent name prefix in WAHA body' do
        let(:waha_body) { "*John Agent*:\n#{original_content}" }

        it 'strips the prefix and finds the message' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
        end
      end

      context 'with extra trailing whitespace in WAHA body' do
        let(:waha_body) { "*John Agent*:\n#{original_content}\n\n\n" }

        it 'finds the message via whitespace normalization' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
        end
      end

      context 'with stray backslash escape in chatwoot content' do
        let(:original_content) { "Bom dia.\n\n\\\n\n" }
        let(:waha_body) { "*Emily Santos*:\nBom dia.\n\n\n" }

        it 'normalizes the backslash artifact and matches' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
        end
      end

      context 'with substring containment (chatwoot inside WAHA body)' do
        let(:waha_body) { "*Agent*:\n#{original_content} extra-suffix" }

        it 'matches via substring fallback' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
        end
      end

      context 'with previous_content from a prior edit' do
        let(:waha_body) { "*Agent*:\nFirst version" }

        before do
          message.update!(content: 'Second version',
                          content_attributes: { 'previous_content' => 'First version' })
        end

        it 'matches against previous_content when current does not match' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
        end
      end

      context 'when only one fromMe candidate exists in tight time window' do
        let(:waha_response) do
          [{
            'id' => 'tight_match_id',
            'fromMe' => true,
            'body' => 'completely different body that should never match by content',
            'timestamp' => message.created_at.to_i + 5
          }]
        end

        it 'falls back to timestamp-only match' do
          expect { described_class.new(message, new_content).perform }.not_to raise_error
          expect(message.reload.source_id).to eq('tight_match_id')
        end
      end

      context 'when multiple fromMe candidates exist in tight time window' do
        let(:waha_response) do
          [
            { 'id' => 'a', 'fromMe' => true, 'body' => 'foo', 'timestamp' => message.created_at.to_i + 2 },
            { 'id' => 'b', 'fromMe' => true, 'body' => 'bar', 'timestamp' => message.created_at.to_i + 5 }
          ]
        end

        it 'does NOT fall back to timestamp-only (ambiguous)' do
          expect { described_class.new(message, new_content).perform }.to raise_error(
            ArgumentError, /not found on WhatsApp/
          )
        end
      end

      context 'when no candidate matches anything' do
        let(:waha_response) do
          [
            { 'id' => 'a', 'fromMe' => true, 'body' => 'totally unrelated', 'timestamp' => message.created_at.to_i - 600 },
            { 'id' => 'b', 'fromMe' => true, 'body' => 'also unrelated', 'timestamp' => message.created_at.to_i - 700 }
          ]
        end

        it 'raises ArgumentError' do
          expect { described_class.new(message, new_content).perform }.to raise_error(
            ArgumentError, /not found on WhatsApp/
          )
        end
      end

      context 'when WAHA returns non-array' do
        let(:waha_response) { { 'error' => 'something broke' } }

        it 'raises ArgumentError' do
          expect { described_class.new(message, new_content).perform }.to raise_error(
            ArgumentError, /not found on WhatsApp/
          )
        end
      end
    end

    context 'when message is too old' do
      let(:waha_body) { original_content }

      before do
        message.update!(created_at: 30.minutes.ago)
      end

      it 'raises ArgumentError before doing any lookup' do
        expect(waha_api).not_to receive(:get_messages)
        expect { described_class.new(message, new_content).perform }.to raise_error(
          ArgumentError, /too old/
        )
      end
    end

    context 'when sender is not the current user' do
      let(:other_user) { create(:user, account: account) }

      before { Current.user = other_user }

      it 'raises ArgumentError' do
        expect { described_class.new(message, new_content).perform }.to raise_error(
          ArgumentError, /sender/
        )
      end
    end
  end
end
