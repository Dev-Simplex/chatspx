require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ScheduledMessagesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:inbox) { conversation.inbox }
  let(:headers) { administrator.create_new_auth_token }

  describe 'GET /api/v1/accounts/:account_id/scheduled_messages' do
    let!(:pending_message) { create_scheduled_message(status: :pending, message: 'Pending message') }
    let!(:cancelled_message) { create_scheduled_message(status: :cancelled, message: 'Cancelled message') }

    it 'returns all upcoming scheduled messages when status is not provided' do
      get api_v1_account_scheduled_messages_url(account_id: account.id), headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |message| message['id'] }
      expect(ids).to include(pending_message.id, cancelled_message.id)
    end

    it 'returns only pending messages when status=pending' do
      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'pending'), headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |message| message['id'] }
      expect(ids).to include(pending_message.id)
      expect(ids).not_to include(cancelled_message.id)
    end

    it 'returns only cancelled messages when status=cancelled' do
      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'cancelled'), headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |message| message['id'] }
      expect(ids).to include(cancelled_message.id)
      expect(ids).not_to include(pending_message.id)
    end

    it 'returns all messages when status=all' do
      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'all'), headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |message| message['id'] }
      expect(ids).to include(pending_message.id, cancelled_message.id)
    end

    it 'returns validation error when status is invalid' do
      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'invalid'), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Status inválido')
    end

    it 'includes attachment metadata in the response payload' do
      blob = create_blob('avatar.png', 'image/png')
      pending_message.attachments.attach(blob)

      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'pending'), headers: headers

      expect(response).to have_http_status(:success)
      message = response.parsed_body.find { |item| item['id'] == pending_message.id }
      expect(message['attachments']).to be_present

      attachment = message['attachments'].first
      expect(attachment).to include(
        'id',
        'blob_signed_id',
        'filename',
        'content_type',
        'byte_size',
        'url'
      )
      expect(attachment['filename']).to eq('avatar.png')
      expect(attachment['content_type']).to eq('image/png')
      expect(attachment['blob_signed_id']).to be_present
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/scheduled_messages/:id' do
    let!(:scheduled_message) { create_scheduled_message(status: :pending) }

    it 'updates a pending scheduled message' do
      new_scheduled_at = 3.hours.from_now.iso8601
      patch api_v1_account_scheduled_message_url(account_id: account.id, id: scheduled_message.id),
            headers: headers,
            params: {
              scheduled_message: {
                message: 'Updated message',
                scheduled_at: new_scheduled_at
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      scheduled_message.reload
      expect(scheduled_message.message).to eq('Updated message')
      expect(scheduled_message.scheduled_at.to_i).to eq(Time.zone.parse(new_scheduled_at).to_i)
    end

    it 'replaces scheduled message attachments on update' do
      old_blob = create_blob('avatar.png', 'image/png')
      new_blob = create_blob('sample.png', 'image/png')
      scheduled_message.attachments.attach(old_blob)

      patch api_v1_account_scheduled_message_url(account_id: account.id, id: scheduled_message.id),
            headers: headers,
            params: {
              scheduled_message: {
                message: 'Updated with new attachment',
                scheduled_at: 4.hours.from_now.iso8601,
                attachments: [new_blob.signed_id]
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      scheduled_message.reload
      expect(scheduled_message.attachments.count).to eq(1)
      expect(scheduled_message.attachments.first.blob_id).to eq(new_blob.id)
    end

    it 'blocks updates for non-pending messages' do
      scheduled_message.update!(status: :sent, sent_at: Time.current)

      patch api_v1_account_scheduled_message_url(account_id: account.id, id: scheduled_message.id),
            headers: headers,
            params: {
              scheduled_message: {
                message: 'Should not update'
              }
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Apenas mensagens pendentes')
      expect(scheduled_message.reload.message).not_to eq('Should not update')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/scheduled_messages/:id' do
    let!(:scheduled_message) { create_scheduled_message(status: :pending) }

    it 'cancels a pending scheduled message' do
      delete api_v1_account_scheduled_message_url(account_id: account.id, id: scheduled_message.id), headers: headers

      expect(response).to have_http_status(:ok)
      expect(scheduled_message.reload.status).to eq('cancelled')
    end

    it 'blocks cancellation for non-pending messages' do
      scheduled_message.update!(status: :failed, error_message: 'External API failure')

      delete api_v1_account_scheduled_message_url(account_id: account.id, id: scheduled_message.id), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Apenas mensagens pendentes')
      expect(scheduled_message.reload.status).to eq('failed')
    end
  end

  private

  def create_scheduled_message(status:, message: 'Scheduled message')
    ScheduledMessage.create!(
      conversation: conversation,
      inbox: inbox,
      message: message,
      status: status,
      scheduled_at: 2.hours.from_now,
      scheduled_by: administrator
    )
  end

  def create_blob(filename, content_type)
    File.open(Rails.root.join("spec/assets/#{filename}")) do |file|
      ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: filename,
        content_type: content_type
      )
    end
  end
end
