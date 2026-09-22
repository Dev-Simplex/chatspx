require 'rails_helper'

RSpec.describe Whatsapp::ResumableUploadService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let!(:inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
  let(:service) { described_class.new(whatsapp_channel.reload) }
  let(:app_id) { '1234567890' }
  let(:session_id) { 'upload:MTphdHRhY2htZW50' }
  let(:file) { StringIO.new('conteudo-binario') }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('WHATSAPP_CLOUD_BASE_URL', anything).and_return('https://graph.facebook.com')
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('')
    inbox.update!(additional_attributes: { 'whatsapp_app_id' => app_id })
  end

  def stub_session(status: 200, body: nil)
    stub_request(:post, %r{graph\.facebook\.com/v22\.0/#{app_id}/uploads})
      .to_return(status: status, body: body || { id: session_id }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_upload(status: 200, body: nil)
    stub_request(:post, "https://graph.facebook.com/v22.0/#{session_id}")
      .to_return(status: status, body: body || { h: '4:handle-da-meta' }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#configured?' do
    it 'is true when the inbox carries an app id' do
      expect(service.configured?).to be(true)
    end

    it 'is false when neither the inbox nor the global config has one' do
      inbox.update!(additional_attributes: {})
      expect(described_class.new(whatsapp_channel.reload).configured?).to be(false)
    end

    it 'falls back to the installation wide app id' do
      inbox.update!(additional_attributes: {})
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('999')
      expect(described_class.new(whatsapp_channel.reload).configured?).to be(true)
    end
  end

  describe '#upload' do
    it 'returns the handle emitted by Meta' do
      stub_session
      stub_upload

      result = service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(result[:success]).to be(true)
      expect(result[:handle]).to eq('4:handle-da-meta')
    end

    # A Graph API usa Bearer em todo o resto, mas o endpoint de upload exige o
    # esquema OAuth. Trocar um pelo outro quebra em produção sem quebrar nada aqui
    # se este exemplo não existir.
    it 'authenticates both steps with the OAuth scheme' do
      stub_session
      stub_upload

      service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(a_request(:post, %r{#{app_id}/uploads})
        .with(headers: { 'Authorization' => "OAuth #{whatsapp_channel.provider_config['api_key']}" })).to have_been_made
      expect(a_request(:post, "https://graph.facebook.com/v22.0/#{session_id}")
        .with(headers: { 'Authorization' => "OAuth #{whatsapp_channel.provider_config['api_key']}" })).to have_been_made
    end

    it 'sends the binary from the start of the file' do
      stub_session
      stub_upload

      service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(a_request(:post, "https://graph.facebook.com/v22.0/#{session_id}")
        .with(headers: { 'file_offset' => '0' }, body: 'conteudo-binario')).to have_been_made
    end

    it 'describes the file when opening the session' do
      stub_session
      stub_upload

      service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(a_request(:post, %r{#{app_id}/uploads})
        .with(query: hash_including('file_name' => 'foto.jpg', 'file_type' => 'image/jpeg',
                                    'file_length' => 'conteudo-binario'.bytesize.to_s))).to have_been_made
    end

    it 'raises when no app id is configured' do
      inbox.update!(additional_attributes: {})

      expect { described_class.new(whatsapp_channel.reload).upload(file, file_name: 'a.jpg', file_type: 'image/jpeg') }
        .to raise_error(described_class::MissingAppIdError)
    end

    it 'raises for a file type Meta does not accept as a header' do
      expect { service.upload(file, file_name: 'planilha.xlsx', file_type: 'application/vnd.ms-excel') }
        .to raise_error(described_class::UnsupportedFileTypeError)
    end

    it 'does not send the binary when the session fails' do
      stub_session(status: 400, body: { error: { message: 'Invalid app' } }.to_json)
      upload = stub_upload

      result = service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(result[:success]).to be(false)
      expect(upload).not_to have_been_requested
    end

    it 'reports failure when Meta refuses the binary' do
      stub_session
      stub_upload(status: 400, body: { error: { message: 'Upload failed' } }.to_json)

      result = service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')

      expect(result[:success]).to be(false)
      expect(result[:response_body]).to include('Upload failed')
    end

    # Resposta 200 sem handle é sucesso aparente: sem este exemplo, o template
    # sairia com `header_handle: [nil]` e a Meta recusaria sem explicação.
    it 'reports failure when Meta answers without a handle' do
      stub_session
      stub_upload(body: {}.to_json)

      expect(service.upload(file, file_name: 'foto.jpg', file_type: 'image/jpeg')[:success]).to be(false)
    end
  end
end
