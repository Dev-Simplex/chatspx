# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::MessageSequenceEnrollmentsController', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe 'POST /api/v1/accounts/:account_id/message_sequence_enrollments' do
    it 'enrolls a conversation into a sequence' do
      expect do
        post "/api/v1/accounts/#{account.id}/message_sequence_enrollments",
             params: { message_sequence_id: sequence.id, conversation_id: conversation.id },
             headers: agent.create_new_auth_token
      end.to change(MessageSequenceEnrollment, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('active')
    end

    it 'returns 422 when already enrolled' do
      create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)

      post "/api/v1/accounts/#{account.id}/message_sequence_enrollments",
           params: { message_sequence_id: sequence.id, conversation_id: conversation.id },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/message_sequence_enrollments' do
    it 'lists enrollments for a conversation' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)

      get "/api/v1/accounts/#{account.id}/message_sequence_enrollments",
          params: { conversation_id: conversation.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['id']).to eq(enrollment.id)
      expect(response.parsed_body.first['message_sequence']['name']).to eq(sequence.name)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/message_sequence_enrollments/:id' do
    it 'cancels the enrollment' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)

      delete "/api/v1/accounts/#{account.id}/message_sequence_enrollments/#{enrollment.id}",
             headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(enrollment.reload).to be_cancelled
    end
  end
end
