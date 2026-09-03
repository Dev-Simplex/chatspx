require 'rails_helper'

RSpec.describe TrackingCredentials::Verifier do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:client) { class_double(HTTParty) }

  # O dublê no lugar do provedor: nenhum spec deste arquivo toca a rede.
  def response_double(code, body)
    instance_double(HTTParty::Response, code: code, parsed_response: body)
  end

  def configure_public_tracking(attributes)
    inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_tracking' => attributes))
  end

  describe 'Meta' do
    let(:credential) do
      create(:tracking_credential, account: account, inbox: inbox,
                                   meta_access_token: 'EAAtoken-de-teste-1234', meta_test_event_code: 'TEST42')
    end

    before { configure_public_tracking('meta_pixel_id' => '111222333') }

    it 'testa com test_event_code e sem gravar evento real' do
      allow(client).to receive(:post).and_return(response_double(200, { 'events_received' => 1 }))

      result = described_class.new(credential, provider: 'meta', client: client).perform

      expect(result[:success]).to be(true)
      expect(client).to have_received(:post) do |url, options|
        expect(url).to eq("#{described_class::META_ENDPOINT}/111222333/events")
        # A trava do aceite: o `test_event_code` no payload e o que mantem o evento FORA da
        # producao. Sem ele a Meta contaria a verificacao como conversao real do cliente.
        expect(options[:body][:test_event_code]).to eq('TEST42')
      end
    end

    # Este e o teste que ACUSA de verdade: sem a guarda, o servico mandaria o evento assim mesmo e
    # a Meta o registraria como conversao real.
    it 'recusa testar quando falta o test_event_code, sem chamar o provedor' do
      allow(client).to receive(:post)
      credential.update!(meta_test_event_code: nil)

      result = described_class.new(credential, provider: 'meta', client: client).perform

      # A ordem importa: o fato que este teste guarda e que o provedor NAO foi chamado. Se esta
      # expectativa vier depois da mensagem, uma regressao falha por outro motivo e esconde o que
      # de fato aconteceu — que um evento real saiu para a Meta.
      expect(client).not_to have_received(:post)
      expect(result[:success]).to be(false)
      expect(result[:message]).to include('test_event_code')
    end

    it 'devolve a mensagem de erro da Meta quando ela recusa' do
      allow(client).to receive(:post).and_return(response_double(400, { 'error' => { 'message' => 'Invalid OAuth access token' } }))

      result = described_class.new(credential, provider: 'meta', client: client).perform

      expect(result[:success]).to be(false)
      expect(result[:message]).to eq('Invalid OAuth access token')
    end

    it 'recusa quando o Pixel ID publico nao esta configurado' do
      allow(client).to receive(:post)
      configure_public_tracking({})

      result = described_class.new(credential, provider: 'meta', client: client).perform

      expect(result[:success]).to be(false)
      expect(client).not_to have_received(:post)
    end
  end

  describe 'GA4' do
    let(:credential) { create(:tracking_credential, account: account, inbox: inbox, ga4_api_secret: 'ga4-secret-abcd') }

    before { configure_public_tracking('ga4_measurement_id' => 'G-ABC123') }

    it 'usa o endpoint de depuracao, que valida sem gravar' do
      allow(client).to receive(:post).and_return(response_double(200, { 'validationMessages' => [] }))

      result = described_class.new(credential, provider: 'ga4', client: client).perform

      expect(result[:success]).to be(true)
      expect(client).to have_received(:post) do |url, _options|
        expect(url).to start_with(described_class::GA4_DEBUG_ENDPOINT)
      end
    end

    # O `/debug/mp/collect` responde 200 mesmo para payload invalido. Tratar o 200 como sucesso
    # aprovaria credencial errada — este teste trava isso.
    it 'reprova quando o GA4 devolve validationMessages, mesmo com 200' do
      allow(client).to receive(:post).and_return(
        response_double(200, { 'validationMessages' => [{ 'description' => 'Measurement id not found' }] })
      )

      result = described_class.new(credential, provider: 'ga4', client: client).perform

      expect(result[:success]).to be(false)
      expect(result[:message]).to eq('Measurement id not found')
    end
  end

  describe 'bordas' do
    let(:credential) { create(:tracking_credential, account: account, inbox: inbox) }

    it 'recusa provedor desconhecido' do
      result = described_class.new(credential, provider: 'tiktok', client: client).perform

      expect(result[:success]).to be(false)
    end

    it 'transforma provedor fora do ar em resultado, nao em excecao' do
      configure_public_tracking('ga4_measurement_id' => 'G-ABC123')
      allow(client).to receive(:post).and_raise(Errno::ECONNREFUSED)

      result = described_class.new(credential, provider: 'ga4', client: client).perform

      expect(result[:success]).to be(false)
    end

    it 'carimba last_verified_at so quando o teste passa' do
      configure_public_tracking('ga4_measurement_id' => 'G-ABC123')
      allow(client).to receive(:post).and_return(response_double(200, { 'validationMessages' => [] }))

      expect { described_class.new(credential, provider: 'ga4', client: client).perform }
        .to change { credential.reload.last_verified_at }.from(nil)
    end
  end
end
