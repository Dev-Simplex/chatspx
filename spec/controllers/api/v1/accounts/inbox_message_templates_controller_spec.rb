require 'rails_helper'

RSpec.describe Api::V1::Accounts::InboxMessageTemplatesController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:whatsapp_inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
  let(:web_widget_inbox) { create(:inbox, account: account) }
  let(:template_service) { instance_double(Whatsapp::TemplateManagementService) }
  let(:upload_service) { instance_double(Whatsapp::ResumableUploadService) }
  let(:file) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  before do
    allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(template_service)
    allow(Whatsapp::ResumableUploadService).to receive(:new).and_return(upload_service)
  end

  describe 'GET /api/v1/accounts/{account.id}/inboxes/{inbox.id}/message_templates' do
    before { allow(template_service).to receive(:list).and_return({ success: true, templates: [] }) }

    # A tela precisa saber se pode oferecer cabeçalho de mídia: sem app id
    # configurado, o upload é impossível e o campo não deve nem aparecer.
    it 'tells whether media upload is available' do
      allow(upload_service).to receive(:configured?).and_return(false)

      get "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp_inbox.id}/message_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['media_upload_enabled']).to be(false)
    end

    it 'reports media upload as available when the channel has an app id' do
      allow(upload_service).to receive(:configured?).and_return(true)

      get "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp_inbox.id}/message_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['media_upload_enabled']).to be(true)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/{inbox.id}/message_templates/upload_media' do
    let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp_inbox.id}/message_templates/upload_media" }

    it 'returns unauthorized without a signed in user' do
      post url, params: { file: file }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns bad request for a channel that is not WhatsApp Cloud' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{web_widget_inbox.id}/message_templates/upload_media",
           params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns the handle emitted by Meta' do
      allow(upload_service).to receive(:upload).and_return({ success: true, handle: '4:handle' })

      post url, params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['handle']).to eq('4:handle')
    end

    it 'requires a file' do
      post url, params: {}, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Texto no lugar do arquivo passava pelo blank? e estourava no
    # original_filename, virando 500 em vez de erro de validação.
    it 'refuses plain text in place of a file' do
      post url, params: { file: 'nao-sou-um-arquivo' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Sem app id o erro tem que explicar o que falta, em vez de estourar 500.
    it 'explains when the channel has no app id configured' do
      allow(upload_service).to receive(:upload).and_raise(Whatsapp::ResumableUploadService::MissingAppIdError,
                                                          'app_id not configured for this channel')

      post url, params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('app_id')
    end

    it 'passes Meta refusal through to the caller' do
      allow(upload_service).to receive(:upload).and_return({ success: false, error: 'Media upload failed',
                                                             response_body: '{"error":{"message":"bad file"}}' })

      post url, params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['details']).to include('bad file')
    end
  end
end
