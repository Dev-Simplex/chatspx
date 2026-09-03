require 'rails_helper'
require_relative '../fake_http_client'

# Bloco 5.11 — os tres clientes de destino: formato do payload, limites da doc e o cliente HTTP
# INJETAVEL. Nenhum exemplo aqui toca a Meta, o GA4 ou o Google Ads: teste que chama API de terceiro
# fica vermelho quando o terceiro tem incidente e verde quando o token expira — mede o mundo, nao o
# codigo.
RSpec.describe Tracking::Destinations::Base do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    conv = create(:conversation, account: account, inbox: inbox)
    conv.update!(
      additional_attributes: conv.additional_attributes.merge('browser' => { 'user_agent' => 'UA/1.0' }),
      custom_attributes: conv.custom_attributes.merge('last_gclid' => 'Cj0-gclid', 'last_page_host' => 'cliente.com.br',
                                                      'last_page_path' => '/planos')
    )
    conv
  end
  let(:event) do
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: conversation.contact,
                                    properties: { 'value' => 350.0, 'currency' => 'BRL' },
                                    dedup_key: 'dest-1', deliver: false)
  end
  let(:settings) do
    Tracking::CredentialResolver::Settings.new(
      meta_pixel_id: '999', meta_access_token: 'token', meta_test_event_code: 'TEST123',
      ga4_measurement_id: 'G-XYZ', ga4_api_secret: 'segredo',
      google_ads_customer_id: '4444', google_ads_conversion_action_id: '55',
      google_ads_developer_token: 'dev', google_ads_access_token: 'ya29'
    )
  end
  let(:client) { FakeHttpClient.new }

  describe Tracking::Destinations::MetaCapi do
    subject(:destino) { described_class.new(event: event, settings: settings, http_client: client) }

    it 'posta em /v{n}/{PIXEL_ID}/events com o token na QUERY, nunca no corpo' do
      destino.deliver!

      expect(client.calls.first[:url]).to eq("https://graph.facebook.com/#{described_class::API_VERSION}/999/events")
      expect(client.calls.first[:query]).to eq(access_token: 'token')
      expect(client.last_body_json).not_to include('token')
    end

    it 'monta o bloco do evento com action_source, event_time do FATO e o event_id' do
      destino.deliver!
      bloco = client.last_body[:data].first

      expect(bloco[:event_name]).to eq('Lead')
      expect(bloco[:action_source]).to eq('website')
      expect(bloco[:event_time]).to eq(event.occurred_at.to_i)
      expect(bloco[:event_id]).to eq(event.event_id)
      expect(bloco[:event_source_url]).to eq('https://cliente.com.br/planos')
      expect(bloco[:custom_data]).to include('value' => 350.0, 'currency' => 'BRL')
    end

    it 'leva o test_event_code quando o modo teste esta ligado (T-C1.8)' do
      destino.deliver!

      expect(client.last_body[:test_event_code]).to eq('TEST123')
    end

    it 'usa o proprio nome chatspx_* quando o evento nao tem equivalente padrao na Meta' do
      outro = Tracking::EventRecorder.record!(name: 'chatspx_orcamento_pedido', account: account,
                                              conversation: conversation, dedup_key: 'x', deliver: false)
      described_class.new(event: outro, settings: settings, http_client: client).deliver!

      expect(client.last_body[:data].first[:event_name]).to eq('chatspx_orcamento_pedido')
    end

    it 'nunca deixa chave de localidade escapar por properties — no fio elas SAO pessoa' do
      sujo = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, conversation: conversation,
                                             properties: { 'ct' => 'sao paulo', 'zp' => '01310100', 'value' => 1 },
                                             dedup_key: 'sujo', deliver: false)
      described_class.new(event: sujo, settings: settings, http_client: client).deliver!

      expect(Tracking::FieldNames.from(client.last_body)).not_to include('ct', 'zp')
      expect(client.last_body_json).not_to include('sao paulo')
      expect(client.last_body[:data].first[:custom_data]).to eq('value' => 1)
    end

    it 'so se diz configurado com pixel E token' do
      expect(destino.configured?).to be(true)
      expect(described_class.new(event: event, settings: nil, http_client: client).configured?).to be(false)
      sem_token = Tracking::CredentialResolver::Settings.new(meta_pixel_id: '999')
      expect(described_class.new(event: event, settings: sem_token, http_client: client).configured?).to be(false)
    end
  end

  describe Tracking::Destinations::Ga4Mp do
    subject(:destino) { described_class.new(event: event, settings: settings, http_client: client) }

    it 'posta em /mp/collect com measurement_id e api_secret na query' do
      destino.deliver!

      expect(client.calls.first[:url]).to eq('https://www.google-analytics.com/mp/collect')
      expect(client.calls.first[:query]).to eq(measurement_id: 'G-XYZ', api_secret: 'segredo')
    end

    it 'leva client_id, consentimento e engagement_time_msec — sem eles o GA4 nao conta a sessao' do
      destino.deliver!
      corpo = client.last_body

      expect(corpo[:client_id]).to be_present
      expect(corpo[:consent]).to eq(ad_user_data: 'GRANTED', ad_personalization: 'GRANTED')
      expect(corpo[:events].first[:name]).to eq('chatspx_lead')
      expect(corpo[:events].first[:params]).to include(engagement_time_msec: 1, event_id: event.event_id)
    end

    it 'aceita 204 com corpo vazio como sucesso, que e o que o MP responde' do
      vazio = FakeHttpClient.new(status: 204, body: {})

      resultado = described_class.new(event: event, settings: settings, http_client: vazio).deliver!

      expect(resultado.status).to eq(:sent)
      expect(resultado.http_status).to eq(204)
    end

    it 'omite o carimbo de tempo alem das 72 h de backdating, em vez de mandar data que o GA4 ignora' do
      velho = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, conversation: conversation,
                                              contact: conversation.contact, occurred_at: 80.hours.ago,
                                              dedup_key: 'velho', deliver: false)
      described_class.new(event: velho, settings: settings, http_client: client).deliver!

      expect(client.last_body).not_to have_key(:timestamp_micros)
    end

    it 'carimba dentro da janela' do
      destino.deliver!

      expect(client.last_body[:timestamp_micros]).to eq((event.occurred_at.to_f * 1_000_000).to_i)
    end

    it 'respeita o teto de 25 parametros por evento' do
      muitos = (1..40).index_with { |n| n }.transform_keys { |n| "p#{n}" }
      gordo = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, conversation: conversation,
                                              contact: conversation.contact, properties: muitos,
                                              dedup_key: 'gordo', deliver: false)
      described_class.new(event: gordo, settings: settings, http_client: client).deliver!

      expect(client.last_body[:events].first[:params].size).to eq(described_class::MAX_PARAMS_PER_EVENT)
    end
  end

  describe Tracking::Destinations::GoogleAds do
    subject(:destino) { described_class.new(event: event, settings: settings, http_client: client) }

    it 'posta uploadClickConversions com developer-token e Bearer nos HEADERS' do
      destino.deliver!

      expect(client.calls.first[:url]).to end_with('/customers/4444:uploadClickConversions')
      expect(client.calls.first[:headers]).to include('Authorization' => 'Bearer ya29', 'developer-token' => 'dev')
      # segredo em header nao pode vazar para o log, que e derivado do CORPO
      expect(Tracking::FieldNames.from(client.last_body)).not_to include('Authorization', 'developer-token')
    end

    it 'usa o event_id como orderId — e o que impede o reenvio de virar duas conversoes' do
      destino.deliver!
      conversao = client.last_body[:conversions].first

      expect(conversao[:orderId]).to eq(event.event_id)
      expect(conversao[:gclid]).to eq('Cj0-gclid')
      expect(conversao[:conversionValue]).to eq(350.0)
      expect(conversao[:currencyCode]).to eq('BRL')
      expect(conversao[:conversionAction]).to eq('customers/4444/conversionActions/55')
      expect(conversao[:conversionDateTime]).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/)
    end

    it 'sem gclid e sem identificador de pessoa nao ha o que mandar: skipped com motivo, nao payload vazio' do
      sem_clique = create(:conversation, account: account, inbox: inbox)
      orfao = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, conversation: sem_clique,
                                              contact: sem_clique.contact, dedup_key: 'orfao', deliver: false)

      resultado = described_class.new(event: orfao, settings: settings, http_client: client).deliver!

      expect(resultado.status).to eq(:skipped)
      expect(resultado.reason).to eq('no_identifier')
      expect(client.called?).to be(false)
    end

    it 'no modo sem PII o bloco de userIdentifiers simplesmente nao existe' do
      destino.deliver!

      expect(client.last_body[:conversions].first).not_to have_key(:userIdentifiers)
    end
  end

  describe 'a traducao de status HTTP, comum aos tres' do
    it '5xx e 429 sao retentaveis; os outros 4xx sao permanentes' do
      { 500 => Tracking::DeliveryError::Retryable, 503 => Tracking::DeliveryError::Retryable,
        429 => Tracking::DeliveryError::Retryable, 408 => Tracking::DeliveryError::Retryable,
        400 => Tracking::DeliveryError::Permanent, 401 => Tracking::DeliveryError::Permanent,
        403 => Tracking::DeliveryError::Permanent }.each do |status, klass|
        destino = Tracking::Destinations::MetaCapi.new(event: event, settings: settings,
                                                       http_client: FakeHttpClient.new(status: status))

        expect { destino.deliver! }.to raise_error(klass), "status #{status} deveria ser #{klass}"
      end
    end

    it 'o codigo do erro nomeia o status, para a DLQ nao dizer so "falhou"' do
      destino = Tracking::Destinations::MetaCapi.new(event: event, settings: settings,
                                                     http_client: FakeHttpClient.new(status: 401))

      expect { destino.deliver! }.to raise_error(Tracking::DeliveryError::Permanent) { |erro|
        expect(erro.code).to eq('http_401')
        expect(erro.http_status).to eq(401)
      }
    end
  end
end
