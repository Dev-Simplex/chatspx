require 'rails_helper'
require_relative '../../services/tracking/fake_http_client'

# Bloco 5.11 — a fila: backoff, teto de tentativas e DLQ visivel.
#
# Os dois exemplos que carregam o bloco sao o do ESGOTAMENTO e o do ERRO PERMANENTE, e os dois rodam
# o retry de verdade (`perform_enqueued_jobs`), nao uma chamada direta ao gancho. A diferenca
# importa: `retry_on` com bloco e facil de escrever de um jeito que nunca dispara — foi exatamente
# isso que aconteceu com o `WebhookJob` desta base enquanto a excecao era engolida antes de subir.
RSpec.describe Tracking::DeliveryJob do
  # A politica e do molde; o destino usado para exercita-la e a Meta CAPI.
  let(:job_class) { Tracking::MetaCapiDeliveryJob }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:event) do
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: conversation.contact,
                                    dedup_key: 'lead-fila', deliver: false)
  end
  let(:delivery) { event.claim_delivery(:meta_capi) }

  let(:settings) do
    Tracking::CredentialResolver::Settings.new(meta_pixel_id: '1', meta_access_token: 't')
  end

  before do
    allow(Tracking::CredentialResolver).to receive(:call).and_return(settings)
    # As fixtures nascem AQUI, fora de qualquer `perform_enqueued_jobs`: criar contato dentro do
    # bloco faria o job de avatar do gravatar rodar inline e bater no WebMock — falha que nao tem
    # nada a ver com a fila de tracking e que levaria meia hora para ser lida como o que e.
    delivery
  end

  def stub_client(client)
    allow(Tracking::HttpClient).to receive(:new).and_return(client)
  end

  describe 'backoff — e espera crescente, nao laco' do
    it 'a primeira espera ja e de 30 s, e nenhuma e zero' do
      esperas = (1..6).map { |n| described_class.backoff_for(n) }

      expect(esperas.first).to eq(30.seconds)
      expect(esperas).to all(be > 0)
    end

    it 'cresce a cada tentativa ate o teto de 1 h' do
      esperas = (1..4).map { |n| described_class.backoff_for(n) }

      expect(esperas).to eq([30.seconds, 2.minutes, 10.minutes, 1.hour])
      expect(esperas.each_cons(2).all? { |a, b| b > a }).to be(true)
      # depois do teto, para de crescer em vez de estourar o indice
      expect(described_class.backoff_for(9)).to eq(1.hour)
    end
  end

  describe 'sucesso' do
    let(:client) { FakeHttpClient.new(status: 200) }

    before { stub_client(client) }

    it 'marca sent, conta a tentativa e grava o log de auditoria' do
      job_class.perform_now(delivery.id)

      expect(delivery.reload).to have_attributes(status: 'sent', http_status: 200, attempts: 1)
      expect(delivery.delivered_at).to be_present
      expect(delivery.field_names).to include('event_id', 'user_data')
    end

    it 'nao entrega de novo o que ja foi entregue' do
      delivery.update!(status: :sent)

      job_class.perform_now(delivery.id)

      expect(client.called?).to be(false)
    end
  end

  describe 'erro RETENTAVEL (5xx) — backoff e, no fim, DLQ' do
    let(:client) { FakeHttpClient.new(status: 503, body: { 'error' => 'unavailable' }) }

    before { stub_client(client) }

    # `perform` direto, sem passar pelos rescue handlers do ActiveJob: e assim que se ve se a
    # excecao SOBE. Por `perform_now` ela nunca apareceria — o proprio `retry_on` a captura, que e
    # exatamente o que deve acontecer, e por isso o exemplo seguinte mede a outra metade.
    it 'marca failed e deixa a excecao SUBIR, senao o retry_on nunca ve nada' do
      expect { job_class.new.perform(delivery.id) }
        .to raise_error(Tracking::DeliveryError::Retryable)

      expect(delivery.reload).to have_attributes(status: 'failed', http_status: 503, error_code: 'http_503')
    end

    it 'e o retry_on a recebe: perform_now nao explode, reenfileira COM ESPERA' do
      clear_enqueued_jobs

      expect { job_class.perform_now(delivery.id) }.not_to raise_error

      retentativas = enqueued_jobs.select { |job| job[:job] == job_class }
      expect(retentativas.size).to eq(1)
      # E o que separa backoff de laco: a reentrega esta agendada para o FUTURO, nao para agora.
      expect(retentativas.first[:at]).to be > Time.current.to_f
    end

    it 'esgota as 5 tentativas e cai na DLQ — visivel, com destino, status e motivo' do
      perform_enqueued_jobs do
        job_class.perform_later(delivery.id)
      end

      expect(delivery.reload).to have_attributes(status: 'dead', attempts: described_class::MAX_ATTEMPTS,
                                                 http_status: 503, error_code: 'http_503')
      expect(client.calls.size).to eq(described_class::MAX_ATTEMPTS)
      expect(TrackingDelivery.dead_letter_queue).to include(delivery)
    end
  end

  describe 'erro PERMANENTE (4xx) — morre na primeira, sem gastar uma hora de backoff' do
    let(:client) { FakeHttpClient.new(status: 400, body: { 'error' => { 'message' => 'Invalid parameter' } }) }

    before { stub_client(client) }

    it 'vai direto para a DLQ com UMA tentativa' do
      perform_enqueued_jobs do
        job_class.perform_later(delivery.id)
      end

      expect(delivery.reload).to have_attributes(status: 'dead', attempts: 1, http_status: 400,
                                                 error_code: 'http_400')
      expect(client.calls.size).to eq(1)
    end

    it 'mas 429 continua sendo retentavel — e o destino pedindo calma, nao payload errado' do
      stub_client(FakeHttpClient.new(status: 429))

      expect { job_class.new.perform(delivery.id) }
        .to raise_error(Tracking::DeliveryError::Retryable)
    end
  end

  describe 'falha de rede' do
    it 'e retentavel: o cliente HTTP traduz Errno em DeliveryError::Retryable' do
      stub_client(FakeHttpClient.new(raise_error: Tracking::DeliveryError::Retryable.new('boom', code: 'network_error')))

      expect { job_class.new.perform(delivery.id) }
        .to raise_error(Tracking::DeliveryError::Retryable)
      expect(delivery.reload.error_code).to eq('network_error')
    end
  end

  describe 'quando nao ha o que entregar' do
    it 'fica skipped com motivo quando a credencial nao existe — e nao tenta nem uma vez' do
      allow(Tracking::CredentialResolver).to receive(:call).and_return(nil)
      client = FakeHttpClient.new
      stub_client(client)

      job_class.perform_now(delivery.id)

      expect(delivery.reload).to have_attributes(status: 'skipped', error_code: 'not_configured', attempts: 0)
      expect(client.called?).to be(false)
    end

    it 'fica skipped quando o evento passou dos 7 dias que a CAPI aceita' do
      velho = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                              conversation: conversation, contact: conversation.contact,
                                              occurred_at: 8.days.ago, dedup_key: 'lead-velho', deliver: false)
      antiga = velho.claim_delivery(:meta_capi)
      client = FakeHttpClient.new
      stub_client(client)

      job_class.perform_now(antiga.id)

      expect(antiga.reload).to have_attributes(status: 'skipped', error_code: 'event_too_old')
      expect(client.called?).to be(false)
    end

    it 'nao explode quando a entrega ja foi apagada junto com o evento' do
      id = delivery.id
      event.destroy!

      expect { job_class.perform_now(id) }.not_to raise_error
    end
  end

  describe 'os tres jobs de destino' do
    it 'cada um aponta para o seu destino, e a politica e uma so' do
      expect(job_class.new.destination_class).to eq(Tracking::Destinations::MetaCapi)
      expect(Tracking::Ga4MpDeliveryJob.new.destination_class).to eq(Tracking::Destinations::Ga4Mp)
      expect(Tracking::GoogleAdsDeliveryJob.new.destination_class).to eq(Tracking::Destinations::GoogleAds)
      expect(Tracking::Ga4MpDeliveryJob.ancestors).to include(described_class)
    end
  end
end
