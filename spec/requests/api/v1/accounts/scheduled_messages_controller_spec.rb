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
    let!(:sent_message) { create_scheduled_message(status: :sent, message: 'Sent message') }
    let!(:failed_message) { create_scheduled_message(status: :failed, message: 'Failed message') }
    let!(:historical_sent_message) do
      create_scheduled_message(
        status: :sent,
        message: 'Historical sent message',
        scheduled_at: 2.hours.ago
      )
    end

    it 'returns all upcoming scheduled messages when status is not provided' do
      get api_v1_account_scheduled_messages_url(account_id: account.id), headers: headers

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |message| message['id'] }
      expect(ids).to include(
        pending_message.id,
        cancelled_message.id,
        sent_message.id,
        failed_message.id
      )
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
      expect(ids).to include(
        pending_message.id,
        cancelled_message.id,
        sent_message.id,
        failed_message.id,
        historical_sent_message.id
      )
    end

    it 'keeps legacy array when mode=cursor and kanban_ux_v2 is disabled' do
      get api_v1_account_scheduled_messages_url(
        account_id: account.id,
        mode: 'cursor',
        status: 'all'
      ), headers: headers

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to be_an(Array)
    end

    context 'when kanban_ux_v2 is enabled' do
      before do
        account.enable_features!('kanban_ux_v2')
      end

      it 'returns cursor payload with meta when mode=cursor' do
        get api_v1_account_scheduled_messages_url(account_id: account.id, mode: 'cursor', status: 'all', limit: 2),
            headers: headers

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body).to have_key('payload')
        expect(body).to have_key('meta')
        expect(body['meta']['limit']).to eq(2)
        expect(body['meta']).to have_key('has_more')
        expect(body['meta']).to have_key('next_cursor')
      end

      it 'paginates cursor results with next_cursor/has_more' do
        get api_v1_account_scheduled_messages_url(account_id: account.id, mode: 'cursor', status: 'all', limit: 2),
            headers: headers

        first_page = response.parsed_body
        expect(first_page['meta']['has_more']).to be(true)
        first_page_ids = first_page['payload'].map { |item| item['id'] }

        get api_v1_account_scheduled_messages_url(
          account_id: account.id,
          mode: 'cursor',
          status: 'all',
          limit: 2,
          cursor: first_page['meta']['next_cursor']
        ), headers: headers

        second_page = response.parsed_body
        second_page_ids = second_page['payload'].map { |item| item['id'] }
        expect(second_page_ids & first_page_ids).to eq([])
      end

      it 'falls back safely on invalid cursor' do
        get api_v1_account_scheduled_messages_url(
          account_id: account.id,
          mode: 'cursor',
          status: 'all',
          cursor: 'invalid-cursor'
        ), headers: headers

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']).to be_an(Array)
      end
    end

    it 'returns validation error when status is invalid' do
      get api_v1_account_scheduled_messages_url(account_id: account.id, status: 'invalid'), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      # O `ScheduledMessagesController` crava TODAS as suas mensagens de erro em ingles
      # (linhas 40, 45, 51, 65, 75, 111...). Passar so esta pelo i18n deixaria o arquivo
      # inconsistente; traduzir o conjunto e tarefa a parte. O spec afirma o que o codigo faz.
      expect(response.parsed_body['error']).to include('Invalid status. Use:')
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

  describe 'POST /api/v1/accounts/:account_id/scheduled_messages' do
    let(:contact) { create(:contact, account: account, phone_number: '+14155550100') }
    let(:inbox_for_contact) { create(:inbox, account: account) }

    it 'creates a scheduled message using contact_id and inbox_id when conversation_id is missing' do
      expect do
        post api_v1_account_scheduled_messages_url(account_id: account.id),
             headers: headers,
             params: {
               scheduled_message: {
                 contact_id: contact.id,
                 inbox_id: inbox_for_contact.id,
                 message: 'Hello contact',
                 scheduled_at: 2.hours.from_now.iso8601
               }
             },
             as: :json
      end.to change(ScheduledMessage, :count).by(1)

      expect(response).to have_http_status(:created)
      scheduled_message = ScheduledMessage.order(:id).last
      expect(scheduled_message.conversation).to be_present
      expect(scheduled_message.conversation.contact_id).to eq(contact.id)
      expect(scheduled_message.conversation.inbox_id).to eq(inbox_for_contact.id)
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

  def create_scheduled_message(status:, message: 'Scheduled message', scheduled_at: 2.hours.from_now)
    ScheduledMessage.create!(
      conversation: conversation,
      inbox: inbox,
      message: message,
      status: status,
      scheduled_at: scheduled_at,
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
