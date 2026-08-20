require 'rails_helper'

# Bloco 5.03 — a API que 5.04, 5.05 e 5.16 chamam. Contrato em docs/tracking/contrato-de-eventos.md §5.
RSpec.describe Tracking::EventRecorder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '.record!' do
    it 'records the fact and returns a persisted event with an event_id' do
      event = described_class.record!(name: 'chatspx_conversation_resolved', account: account,
                                      inbox: inbox, conversation: conversation,
                                      properties: { resolution: 'agent', duration_s: 428 })

      expect(event).to be_persisted
      expect(event.event_id).to be_present
      expect(event.properties).to eq({ 'resolution' => 'agent', 'duration_s' => 428 })
      expect(event.account_id).to eq(account.id)
      expect(event.conversation_id).to eq(conversation.id)
    end

    it 'is idempotent: the same dedup_key returns the SAME record, without creating a second' do
      first = described_class.record!(name: 'chatspx_lead', account: account, dedup_key: 'contato:7:lead')
      second = nil

      expect { second = described_class.record!(name: 'chatspx_lead', account: account, dedup_key: 'contato:7:lead') }
        .not_to change(TrackingEvent, :count)
      expect(second.id).to eq(first.id)
      expect(second.event_id).to eq(first.event_id)
    end

    it 'is idempotent under the retry of a job: same fact, same timestamp, one record' do
      moment = Time.zone.parse('2026-08-18 09:00:00')

      first = described_class.record!(name: 'chatspx_conversation_resolved', account: account,
                                      conversation: conversation, occurred_at: moment)
      second = described_class.record!(name: 'chatspx_conversation_resolved', account: account,
                                       conversation: conversation, occurred_at: moment)

      expect(TrackingEvent.count).to eq(1)
      expect(second.id).to eq(first.id)
    end

    it 'records two genuine facts about the same conversation at different moments' do
      described_class.record!(name: 'chatspx_conversation_resolved', account: account,
                              conversation: conversation, occurred_at: Time.zone.parse('2026-08-18 09:00:00'))
      described_class.record!(name: 'chatspx_conversation_resolved', account: account,
                              conversation: conversation, occurred_at: Time.zone.parse('2026-08-18 11:00:00'))

      expect(TrackingEvent.count).to eq(2)
    end

    it 'accepts the source of the emission' do
      widget_event = described_class.record!(name: 'chatspx_widget_opened', account: account,
                                             source: :widget, dedup_key: 'w1')
      site_event = described_class.record!(name: 'chatspx_orcamento_pedido', account: account,
                                           source: :site, dedup_key: 's1')

      expect(widget_event.source).to eq('widget')
      expect(site_event.source).to eq('site')
    end

    it 'raises RecordInvalid when the name violates the contract' do
      expect { described_class.record!(name: 'conversation_resolved', account: account) }
        .to raise_error(ActiveRecord::RecordInvalid, /chatspx_/)
    end

    it 'raises when the account is missing, because the data would have no owner' do
      expect { described_class.record!(name: 'chatspx_lead', account: nil) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'TrackingEvent#claim_delivery' do
    let(:event) { described_class.record!(name: 'chatspx_lead', account: account, dedup_key: 'lead-1') }

    it 'returns the delivery when the caller wins the race' do
      delivery = event.claim_delivery(:meta_capi)

      expect(delivery).to be_persisted
      expect(delivery.destination).to eq('meta_capi')
      expect(delivery.status).to eq('pending')
    end

    it 'returns nil on the second claim — this is what stops a double delivery' do
      event.claim_delivery(:meta_capi)

      expect(event.claim_delivery(:meta_capi)).to be_nil
      expect(event.tracking_deliveries.where(destination: :meta_capi).count).to eq(1)
    end

    it 'returns nil even when the first claim came from ANOTHER instance of the same event' do
      # E o cenario de dois workers: cada um carregou o proprio objeto e nenhum viu o do outro.
      event.claim_delivery(:meta_capi)
      other_worker = TrackingEvent.find(event.id)

      expect(other_worker.claim_delivery(:meta_capi)).to be_nil
      expect(TrackingDelivery.where(tracking_event_id: event.id, destination: :meta_capi).count).to eq(1)
    end

    it 'still allows a claim to a different destination' do
      event.claim_delivery(:meta_capi)

      expect(event.claim_delivery(:ga4_mp)).to be_persisted
    end

    it 'refuses a destination that is not in the contract' do
      expect { event.claim_delivery(:tiktok) }.to raise_error(ArgumentError, /tiktok/)
    end
  end
end
