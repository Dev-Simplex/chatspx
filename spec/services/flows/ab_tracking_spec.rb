# frozen_string_literal: true

require 'rails_helper'

# 6.05 — os tres fatos do A/B, e a TRAVA que herdamos do 5.03.
#
# O centro deste arquivo e a idempotencia: o job do dispatcher e retentado, e sem chave
# natural o retry viraria uma segunda conversao. Num A/B isso nao e ruido — e a variante
# errada ganhando, porque quem retenta mais e quem falhou mais.
RSpec.describe Flows::AbTracking do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) do
    create(:flow, account: account, trigger_type: :widget_prechat,
                  trigger_config: { 'experiment' => { 'key' => 'checkout' } })
  end

  def eventos(name)
    TrackingEvent.where(account_id: account.id, name: name)
  end

  describe 'the inherited lock — the same fact recorded twice is one row' do
    # O RELOGIO ANDA ENTRE AS CHAMADAS, e isso e o teste, nao cenario.
    #
    # A derivacao padrao da dedup_key (§4.2 do contrato) usa `occurred_at.to_i`. Duas
    # chamadas no MESMO segundo colidem nela sozinhas — entao um teste que chamasse
    # `record` tres vezes seguidas ficaria verde COM e SEM a chave explicita, e nao
    # provaria nada. O retry de um job Sidekiq acontece segundos ou minutos depois; e
    # exatamente ai que a derivacao deixa de proteger e a chave natural passa a ser a
    # unica coisa entre o cliente e a conversao contada duas vezes.
    def retentar(intervalo: 30.seconds, &registro)
      yield
      travel(intervalo, &registro)
    end

    it 'counts one conversion when the job is retried half a minute later' do
      retentar { described_class.record_conversion(flow: flow, conversation: conversation) }

      expect(eventos(described_class::CONVERTED).count).to eq(1)
    end

    it 'counts one exposure per visitor even if the runner starts again minutes later' do
      retentar(intervalo: 5.minutes) { described_class.record_assignment(flow: flow, conversation: conversation) }

      expect(eventos(described_class::ASSIGNED).count).to eq(1)
    end

    it 'counts one step per node even when the walk passes it again after a wait' do
      retentar(intervalo: 2.hours) do
        described_class.record_step(flow: flow, conversation: conversation, node_id: 'pergunta-nome')
      end

      expect(eventos(described_class::STEP).count).to eq(1)
    end

    it 'still counts two DIFFERENT steps as two — the key is the node, not the run' do
      described_class.record_step(flow: flow, conversation: conversation, node_id: 'pergunta-nome')
      described_class.record_step(flow: flow, conversation: conversation, node_id: 'pergunta-email')

      expect(eventos(described_class::STEP).count).to eq(2)
    end

    it 'still counts two DIFFERENT visitors as two' do
      outra = create(:conversation, account: account, inbox: inbox)

      described_class.record_conversion(flow: flow, conversation: conversation)
      described_class.record_conversion(flow: flow, conversation: outra)

      expect(eventos(described_class::CONVERTED).count).to eq(2)
    end
  end

  describe 'what a flow outside any experiment emits' do
    let(:sem_experimento) { create(:flow, account: account, trigger_type: :widget_prechat, trigger_config: {}) }

    it 'emits nothing at all — the state of the whole fleet today' do
      described_class.record_assignment(flow: sem_experimento, conversation: conversation)
      described_class.record_step(flow: sem_experimento, conversation: conversation, node_id: 'n1')
      described_class.record_conversion(flow: sem_experimento, conversation: conversation)

      expect(TrackingEvent.where(name: described_class::NAMES).count).to eq(0)
    end
  end

  describe 'the properties, which are what the report reads' do
    it 'carries the experiment, the variant and the version under which the number was obtained' do
      described_class.record_assignment(flow: flow, conversation: conversation)

      properties = eventos(described_class::ASSIGNED).first.properties
      expect(properties['experiment']).to eq('checkout')
      expect(properties['variant']).to eq(flow.id)
      expect(properties['variant_version']).to eq(flow.version)
    end

    it 'names the node on a step event, which is the axis of the funnel' do
      described_class.record_step(flow: flow, conversation: conversation, node_id: 'pergunta-email')

      expect(eventos(described_class::STEP).first.properties['node_id']).to eq('pergunta-email')
    end

    # ACEITE: publicar uma variante nova nao invalida o historico da anterior.
    it 'keeps the old rows readable at their own version after the variant is republished' do
      described_class.record_conversion(flow: flow, conversation: conversation)
      flow.update!(version: 2)
      described_class.record_conversion(flow: flow, conversation: create(:conversation, account: account, inbox: inbox))

      expect(eventos(described_class::CONVERTED).map { |e| e.properties['variant_version'] }.sort).to eq([1, 2])
    end
  end

  describe 'best-effort — measuring the experiment never breaks the visitor' do
    it 'swallows a failure of the recorder instead of aborting the walk' do
      allow(Tracking::EventRecorder).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, 'banco caiu')

      expect { described_class.record_conversion(flow: flow, conversation: conversation) }.not_to raise_error
      expect(eventos(described_class::CONVERTED).count).to eq(0)
    end

    it 'records nothing, and does not blow up, without a conversation to attach the fact to' do
      expect { described_class.record_assignment(flow: flow, conversation: nil) }.not_to raise_error
      expect(eventos(described_class::ASSIGNED).count).to eq(0)
    end
  end
end
