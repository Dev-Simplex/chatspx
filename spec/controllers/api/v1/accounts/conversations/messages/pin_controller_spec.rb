require 'rails_helper'

RSpec.describe 'Conversation Message Pin API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  def pin_url(message_id)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message_id}/pin"
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/pin' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post pin_url(message.id), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'pins the message (200 + pinned_message_ids)' do
        post pin_url(message.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['conversation_id']).to eq(conversation.display_id)
        expect(body['pinned_message_ids']).to eq([message.id])

        conversation.reload
        expect(Messages::PinService.pinned_ids(conversation)).to eq([message.id])
      end

      it 'is idempotent when pinning the same message twice' do
        post pin_url(message.id), headers: agent.create_new_auth_token, as: :json
        post pin_url(message.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['pinned_message_ids']).to eq([message.id])
      end

      it 'returns 422 when cap of 3 is reached' do
        message_b = create(:message, conversation: conversation, account: account, inbox: inbox)
        message_c = create(:message, conversation: conversation, account: account, inbox: inbox)
        message_d = create(:message, conversation: conversation, account: account, inbox: inbox)

        [message.id, message_b.id, message_c.id].each do |mid|
          post pin_url(mid), headers: agent.create_new_auth_token, as: :json
          expect(response).to have_http_status(:success)
        end

        post pin_url(message_d.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['error']).to match(/pin_limit_reached/)
        expect(body['pinned_message_ids']).to match_array([message.id, message_b.id, message_c.id])
      end

      it 'returns 404 when the message does not exist' do
        post pin_url(999_999), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 when the message belongs to a different conversation' do
        other_conv = create(:conversation, account: account, inbox: inbox)
        foreign_msg = create(:message, conversation: other_conv, account: account, inbox: inbox)

        post pin_url(foreign_msg.id), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'dispatches CONVERSATION_PIN_ADDED to ActionCable broadcast' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).at_least(:once) do |tokens, name, _payload|
          if name == Events::Types::CONVERSATION_PIN_ADDED
            expect(tokens).to include(agent.pubsub_token)
          end
        end

        post pin_url(message.id), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/pin' do
    before do
      Messages::PinService.new(conversation: conversation, message_id: message.id).add
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete pin_url(message.id), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'unpins the message and returns the updated array' do
        delete pin_url(message.id), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['pinned_message_ids']).to eq([])

        conversation.reload
        expect(Messages::PinService.pinned_ids(conversation)).to eq([])
      end

      it 'is idempotent when the message is not pinned' do
        delete pin_url(message.id), headers: agent.create_new_auth_token, as: :json

        # second delete on the same id is a no-op
        delete pin_url(message.id), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['pinned_message_ids']).to eq([])
      end

      it 'returns 404 when the message does not exist' do
        delete pin_url(999_999), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
