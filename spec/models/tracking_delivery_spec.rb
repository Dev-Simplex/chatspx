require 'rails_helper'

# Bloco 5.03 — uma linha por (evento, destino). O indice unico e o aceite do bloco.
RSpec.describe TrackingDelivery, type: :model do
  let(:account) { create(:account) }
  let(:event) do
    TrackingEvent.create!(name: 'chatspx_lead', account: account, dedup_key: 'fato-1')
  end

  describe 'the unique index on (tracking_event_id, destination)' do
    it 'accepts one delivery per destination' do
      described_class.create!(tracking_event: event, destination: :meta_capi)
      described_class.create!(tracking_event: event, destination: :ga4_mp)

      expect(event.reload.tracking_deliveries.count).to eq(2)
    end

    it 'refuses a second delivery to the same destination — at the DATABASE, not in Ruby' do
      described_class.create!(tracking_event: event, destination: :meta_capi)

      expect { described_class.create!(tracking_event: event, destination: :meta_capi) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'lets a different event deliver to the same destination' do
      other = TrackingEvent.create!(name: 'chatspx_lead', account: account, dedup_key: 'fato-2')
      described_class.create!(tracking_event: event, destination: :meta_capi)

      expect(described_class.create(tracking_event: other, destination: :meta_capi)).to be_persisted
    end
  end

  describe 'the six destinations of the contract' do
    it 'names all six, client-side and server-side' do
      expect(described_class.destinations.keys)
        .to eq(%w[data_layer meta_pixel ga4_gtag meta_capi ga4_mp google_ads])
    end
  end

  describe 'defaults declared in the contract' do
    it 'starts pending with zero attempts and empty field_names' do
      delivery = described_class.create!(tracking_event: event, destination: :meta_capi)

      expect(delivery.reload).to have_attributes(status: 'pending', attempts: 0, field_names: [],
                                                 http_status: nil, error_code: nil, emq: nil,
                                                 delivered_at: nil, last_attempted_at: nil)
    end
  end

  describe 'field_names records NAMES, never values (T-C8.1, e 5.12 verifica isto)' do
    it 'keeps the list of field names it was given' do
      delivery = described_class.create!(tracking_event: event, destination: :meta_capi,
                                         field_names: %w[em ph fbp client_ip_address])

      expect(delivery.reload.field_names).to eq(%w[em ph fbp client_ip_address])
    end

    it 'refuses anything that is not a flat list of strings' do
      delivery = described_class.new(tracking_event: event, destination: :meta_capi,
                                     field_names: { 'em' => 'alguem@exemplo.com' })

      expect(delivery).not_to be_valid
      expect(delivery.errors[:field_names]).to eq(['deve ser uma lista de nomes de campo, nunca valores'])
    end
  end

  describe 'deleting the event deletes its deliveries' do
    it 'cascades, because a delivery does not exist without its event' do
      described_class.create!(tracking_event: event, destination: :meta_capi)

      expect { event.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'the DLQ is queryable' do
    it 'finds what died after the last retry' do
      described_class.create!(tracking_event: event, destination: :meta_capi, status: :dead,
                              attempts: 5, error_code: 'http_500')
      described_class.create!(tracking_event: event, destination: :ga4_mp, status: :sent)

      expect(described_class.dead.pluck(:destination)).to eq(['meta_capi'])
    end
  end
end
