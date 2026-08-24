require 'rails_helper'
require_relative 'fake_http_client'
require_relative 'meta_counter'

# Bloco 5.13 — deduplicacao de verdade: mesmo `event_id` nos dois caminhos, guarda da janela de 48 h
# e um TESTE DE CONTAGEM.
#
# O teste de contagem existe porque "os dois lados mandam o mesmo id" e uma afirmacao sobre o
# payload, e o que o cliente ve e um NUMERO. Entre uma coisa e outra ha a janela de 48 h: passada
# ela, a Meta esqueceu o primeiro evento e o segundo entra como novo — dois payloads perfeitamente
# corretos produzindo uma conversao inflada, sem erro em lugar nenhum.
#
# `MetaCounter` (em `meta_counter.rb`) e a Meta como ela conta: dedup por (`event_id`, `event_name`)
# DENTRO de 48 h, evento novo fora dela. E o unico jeito de o spec falar do numero, e nao do payload.
RSpec.describe Tracking::DedupWindow do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:contact) { conversation.contact }

  let(:settings) do
    Tracking::CredentialResolver::Settings.new(meta_pixel_id: '1', meta_access_token: 't')
  end
  let(:http_client) { FakeHttpClient.new }
  let(:counter) { MetaCounter.new }

  # O fato aconteceu ha `age`; o navegador contou na hora.
  def build_paired_event(age:)
    event = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                            conversation: conversation, contact: contact,
                                            occurred_at: age.ago, dedup_key: "lead-#{age.to_i}",
                                            deliver: false)
    browser = event.claim_delivery(:meta_pixel)
    browser.update!(status: :sent, delivered_at: event.occurred_at)
    # o navegador contou AQUI, com o event_id do servidor (T-C6.1/T-C6.2)
    counter.receive(event_id: event.event_id, event_name: 'Lead', at: event.occurred_at)
    event
  end

  def run_server_leg(event)
    delivery = event.claim_delivery(:meta_capi)
    Tracking::MetaCapiDeliveryJob.perform_now(delivery.id)
    body = http_client.last_body
    if body.present?
      block = body[:data].first
      counter.receive(event_id: block[:event_id], event_name: block[:event_name], at: Time.current)
    end
    delivery.reload
  end

  before do
    allow(Tracking::CredentialResolver).to receive(:call).and_return(settings)
    allow(Tracking::HttpClient).to receive(:new).and_return(http_client)
  end

  describe 'o mesmo event_id nos dois caminhos (T-C6.2)' do
    it 'o payload server-side leva o event_id que o navegador ja usou' do
      event = build_paired_event(age: 1.hour)
      run_server_leg(event)

      expect(http_client.last_body[:data].first[:event_id]).to eq(event.event_id)
    end
  end

  describe 'CONTAGEM — dentro da janela, os dois caminhos contam UM' do
    it 'nao dobra o total' do
      event = build_paired_event(age: 1.hour)
      delivery = run_server_leg(event)

      expect(delivery.status).to eq('sent')
      expect(counter.counted).to eq(1)
    end
  end

  describe 'CONTAGEM — fora da janela, SEM a guarda, o total DOBRA' do
    # Este exemplo e o vermelho que da sentido ao verde do proximo. Ele desliga a guarda e mostra o
    # numero que o cliente veria: dois. Sem ele, "o total nao dobra" tambem seria verdade num
    # cenario em que nada foi entregue.
    it 'a mesma conversao entra duas vezes quando a guarda nao age' do
      allow(described_class).to receive(:skip_reason).and_return(nil)
      event = build_paired_event(age: 50.hours)

      delivery = run_server_leg(event)

      expect(delivery.status).to eq('sent')
      expect(counter.counted).to eq(2)
    end
  end

  describe 'CONTAGEM — fora da janela, COM a guarda, o total continua UM' do
    it 'nao manda como par: fica skipped, com o motivo gravado e visivel' do
      event = build_paired_event(age: 50.hours)

      delivery = run_server_leg(event)

      expect(delivery.status).to eq('skipped')
      expect(delivery.error_code).to eq('dedup_window_expired')
      expect(http_client.called?).to be(false)
      expect(counter.counted).to eq(1)
    end
  end

  describe 'o outro ramo da regra: evento server-only atravessa a janela' do
    it 'entrega normalmente quando o navegador NUNCA contou — nao ha o que dobrar' do
      event = Tracking::EventRecorder.record!(name: 'chatspx_deal_won', account: account, inbox: inbox,
                                              conversation: conversation, contact: contact,
                                              occurred_at: 50.hours.ago, dedup_key: 'won-1', deliver: false)

      delivery = run_server_leg(event)

      expect(delivery.status).to eq('sent')
      expect(counter.counted).to eq(1)
    end

    it 'entrega tambem quando o bloqueador impediu o navegador — o caso que o server-side existe para salvar' do
      event = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                              conversation: conversation, contact: contact,
                                              occurred_at: 50.hours.ago, dedup_key: 'lead-bloqueado', deliver: false)
      # a entrega client-side foi RESERVADA mas nunca saiu: o bloqueador comeu o pixel
      event.claim_delivery(:meta_pixel).update!(status: :failed)

      expect(described_class.skip_reason(event)).to be_nil
      expect(run_server_leg(event).status).to eq('sent')
    end
  end

  describe 'as pecas da regra, isoladas' do
    it 'expired? mede a idade do FATO, nao a da entrega' do
      event = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account,
                                              occurred_at: 47.hours.ago, dedup_key: 'a', deliver: false)
      velho = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account,
                                              occurred_at: 49.hours.ago, dedup_key: 'b', deliver: false)

      expect(described_class.expired?(event)).to be(false)
      expect(described_class.expired?(velho)).to be(true)
    end

    it 'paired? exige entrega client-side ENVIADA, nao so um nome na lista' do
      event = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, dedup_key: 'c', deliver: false)

      expect(described_class.paired?(event)).to be(false)

      event.claim_delivery(:meta_pixel).update!(status: :sent)
      expect(described_class.paired?(event.reload)).to be(true)
    end

    it 'evento que nunca propaga event_id nao forma par nem com entrega client-side' do
      event = Tracking::EventRecorder.record!(name: 'chatspx_widget_opened', account: account,
                                              dedup_key: 'd', deliver: false)
      event.claim_delivery(:data_layer).update!(status: :sent)

      expect(described_class.paired?(event.reload)).to be(false)
    end
  end
end
