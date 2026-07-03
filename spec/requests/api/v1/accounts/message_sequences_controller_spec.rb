# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::MessageSequencesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/message_sequences' do
    let!(:sequence) { create(:message_sequence, :with_steps, account: account) }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/message_sequences"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'lists sequences with their steps' do
        get "/api/v1/accounts/#{account.id}/message_sequences", headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.first['id']).to eq(sequence.id)
        expect(body.first['steps'].size).to eq(2)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/message_sequences' do
    let(:params) do
      {
        message_sequence: {
          name: 'Recuperação de carrinho',
          exit_conditions: { on_customer_reply: true },
          steps_attributes: [
            { position: 1, delay_minutes: 0, content: 'Oi {{contact.first_name}}!' },
            { position: 2, delay_minutes: 1440, content: 'Ainda tem interesse?' }
          ]
        }
      }
    end

    it 'lets an administrator create a sequence with steps' do
      expect do
        post "/api/v1/accounts/#{account.id}/message_sequences", params: params,
                                                                 headers: administrator.create_new_auth_token
      end.to change(MessageSequence, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['steps'].size).to eq(2)
      expect(MessageSequence.last.created_by).to eq(administrator)
    end

    it 'forbids an agent from creating a sequence' do
      post "/api/v1/accounts/#{account.id}/message_sequences", params: params,
                                                               headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/message_sequences/:id' do
    let!(:sequence) { create(:message_sequence, :with_steps, account: account) }

    it 'updates the sequence and removes a step via _destroy' do
      step_to_remove = sequence.steps.last
      params = {
        message_sequence: {
          name: 'Renomeada',
          steps_attributes: [{ id: step_to_remove.id, _destroy: true }]
        }
      }

      patch "/api/v1/accounts/#{account.id}/message_sequences/#{sequence.id}", params: params,
                                                                               headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(sequence.reload.name).to eq('Renomeada')
      expect(sequence.steps.count).to eq(1)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/message_sequences/:id' do
    let!(:sequence) { create(:message_sequence, account: account) }

    it 'deletes the sequence' do
      expect do
        delete "/api/v1/accounts/#{account.id}/message_sequences/#{sequence.id}",
               headers: administrator.create_new_auth_token
      end.to change(MessageSequence, :count).by(-1)
    end
  end
end
