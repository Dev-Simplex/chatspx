require 'rails_helper'

# Bloco 5.11 — o leque: primeiro RESERVA (indice unico), depois enfileira.
#
# A ordem e o unico jeito de dois workers concorrentes nao produzirem dois jobs para o mesmo par
# (evento, destino). O exemplo do "segundo despacho" e a prova: ele roda o leque duas vezes e conta
# os jobs.
RSpec.describe Tracking::DeliveryDispatcher do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:event) do
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: conversation.contact,
                                    dedup_key: 'leque-1', deliver: false)
  end

  let(:todas) do
    Tracking::CredentialResolver::Settings.new(
      meta_pixel_id: '1', meta_access_token: 't',
      ga4_measurement_id: 'G-1', ga4_api_secret: 's',
      google_ads_customer_id: '2', google_ads_conversion_action_id: '3',
      google_ads_developer_token: 'd', google_ads_access_token: 'a'
    )
  end

  def jobs_de_tracking
    enqueued_jobs.select { |job| job[:job] <= Tracking::DeliveryJob }
  end

  describe 'sem credencial — o estado de hoje, enquanto o bloco 5.02 nao aterrissa' do
    before { allow(Tracking::CredentialResolver).to receive(:call).and_return(nil) }

    it 'nao reserva, nao enfileira e nao escreve nada' do
      clear_enqueued_jobs

      expect { described_class.call(event) }.not_to change(TrackingDelivery, :count)
      expect(jobs_de_tracking).to be_empty
    end
  end

  describe 'com as tres credenciais' do
    before do
      allow(Tracking::CredentialResolver).to receive(:call).and_return(todas)
      event
      clear_enqueued_jobs
    end

    it 'reserva e enfileira um job por destino server-side' do
      destinos = described_class.call(event)

      expect(destinos).to eq(%i[meta_capi ga4_mp google_ads])
      expect(event.tracking_deliveries.pluck(:destination)).to match_array(%w[meta_capi ga4_mp google_ads])
      expect(jobs_de_tracking.map { |job| job[:job] })
        .to contain_exactly(Tracking::MetaCapiDeliveryJob, Tracking::Ga4MpDeliveryJob, Tracking::GoogleAdsDeliveryJob)
    end

    it 'o SEGUNDO despacho nao enfileira nada — quem perde a corrida do indice unico nao entrega' do
      described_class.call(event)
      clear_enqueued_jobs

      expect { described_class.call(event) }.not_to change(TrackingDelivery, :count)
      expect(jobs_de_tracking).to be_empty
    end

    it 'o job recebe o id da entrega, nunca a credencial — segredo em fila e segredo em backup de fila' do
      described_class.call(event)

      argumentos = jobs_de_tracking.flat_map { |job| job[:args] }
      expect(argumentos).to match_array(event.tracking_deliveries.pluck(:id))
      expect(argumentos.map(&:class).uniq).to eq([Integer])
    end
  end

  describe 'com credencial parcial' do
    it 'so enfileira o destino configurado' do
      so_meta = Tracking::CredentialResolver::Settings.new(meta_pixel_id: '1', meta_access_token: 't')
      allow(Tracking::CredentialResolver).to receive(:call).and_return(so_meta)
      event
      clear_enqueued_jobs

      expect(described_class.call(event)).to eq([:meta_capi])
      expect(event.tracking_deliveries.pluck(:destination)).to eq(['meta_capi'])
    end
  end

  describe 'a ligacao com o registro do fato (Tracking::EventRecorder)' do
    before { allow(Tracking::CredentialResolver).to receive(:call).and_return(todas) }

    it 'registrar um fato despacha a fila' do
      clear_enqueued_jobs

      novo = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                             conversation: conversation, contact: conversation.contact,
                                             dedup_key: 'leque-2')

      expect(novo.tracking_deliveries.count).to eq(3)
      expect(jobs_de_tracking.size).to eq(3)
    end

    it 'deliver: false registra sem despachar — e como as outras trilhas testam o 5.03 isolado' do
      clear_enqueued_jobs

      Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                      conversation: conversation, contact: conversation.contact,
                                      dedup_key: 'leque-3', deliver: false)

      expect(jobs_de_tracking).to be_empty
    end

    it 'falha ao despachar NAO desfaz o registro do fato — observabilidade nao quebra o produto' do
      allow(described_class).to receive(:call).and_raise(StandardError, 'fila fora do ar')

      registrado = nil
      expect do
        registrado = Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                                     conversation: conversation, contact: conversation.contact,
                                                     dedup_key: 'leque-4')
      end.not_to raise_error

      expect(registrado).to be_persisted
    end
  end
end
