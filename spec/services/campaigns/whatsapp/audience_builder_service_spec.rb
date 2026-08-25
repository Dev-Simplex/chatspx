# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::Whatsapp::AudienceBuilderService do
  let(:account) { create(:account) }
  # Inbox montada a mao (e nao pela trait :whatsapp do factory) porque a trait cria um
  # canal 360dialog, cujo after_create bate na rede pra registrar o webhook.
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }

  # +55 66 99292-7211 -> canonico 6692927211 (DDD + ultimos 8 digitos).
  let(:phone) { '+5566992927211' }
  let(:canonical) { '6692927211' }
  let(:rows) { [{ name: 'Fulano', phone: phone }] }

  def build_audience(list = rows, blocklist_phones: nil)
    described_class.new(campaign: campaign, rows: list, blocklist_phones: blocklist_phones).perform
  end

  def suppress!(contact, category: 'marketing', expires_at: nil)
    create(:contact_flow_suppression, contact: contact, account: account, category: category, expires_at: expires_at)
  end

  # Destinatario ja disparado em OUTRA campanha da conta: o motivo `ja_disparado`.
  def already_dispatched!
    other = create(:campaign, account: account, inbox: inbox)
    CampaignRecipient.create!(campaign: other, account: account, phone_number: phone,
                              canonical_phone: canonical, status: :sent)
  end

  describe 'opt-out (ContactFlowSuppression)' do
    let!(:contact) { create(:contact, account: account, phone_number: phone) }

    it 'descarta quem tem supressao ativa com o motivo optou_por_sair' do
      suppress!(contact)

      result = build_audience

      expect(result.accepted).to be_empty
      expect(result.rejected).to contain_exactly(hash_including(phone: phone, reason: 'optou_por_sair'))
    end

    it 'nao descarta quando a supressao ja expirou' do
      suppress!(contact, expires_at: 1.hour.ago)

      result = build_audience

      expect(result.rejected).to be_empty
      expect(result.accepted.map { |entry| entry[:canonical] }).to eq([canonical])
    end

    it 'descarta pela supressao catch-all `all`' do
      suppress!(contact, category: 'all')

      expect(build_audience.rejected.first[:reason]).to eq('optou_por_sair')
    end

    it 'nao descarta quando a supressao e apenas de utility' do
      suppress!(contact, category: 'utility')

      result = build_audience

      expect(result.rejected).to be_empty
      expect(result.accepted.size).to eq(1)
    end

    it 'aceita contato sem nenhuma supressao' do
      result = build_audience

      expect(result.rejected).to be_empty
      expect(result.accepted.map { |entry| entry[:phone] }).to eq([phone])
    end

    it 'encontra a supressao mesmo quando a ficha nasceu sem o 9o digito' do
      contact.update!(phone_number: '+556692927211')
      suppress!(contact)

      expect(build_audience.rejected.first[:reason]).to eq('optou_por_sair')
    end
  end

  describe 'ordem dos motivos' do
    let!(:contact) { create(:contact, account: account, phone_number: phone) }

    # Protege a MEDICAO de compliance: reportado como ja_disparado, quem pediu PARAR
    # depois de ter levado um disparo sumiria da contagem de opt-out.
    it 'reporta optou_por_sair, nao ja_disparado, quando o contato e as duas coisas' do
      suppress!(contact)
      already_dispatched!

      expect(build_audience.rejected.first[:reason]).to eq('optou_por_sair')
    end

    it 'reporta ja_disparado quando nao ha supressao' do
      already_dispatched!

      expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
    end

    # Blocklist explicita (CSV de corretores) continua vindo antes do opt-out.
    it 'reporta bloqueado quando o numero esta na blocklist e suprimido' do
      suppress!(contact)

      result = build_audience(rows, blocklist_phones: [phone])

      expect(result.rejected.first[:reason]).to eq('bloqueado')
    end
  end

  # O motor ANTIGO (Spx::Tozi::DisparoLeadJob) carimba `campaign_id` na CONVERSA e nao cria
  # linha em `campaign_recipients`. Ler so a tabela nova era o ponto cego que deixou 294
  # pessoas levarem o Urban depois de ja terem levado o disparo de junho/2026.
  describe 'dedup pelos dois motores' do
    let!(:contact) { create(:contact, account: account, phone_number: phone) }

    def dispatched_by_old_engine!(scheduled_at: Time.current)
      other = create(:campaign, account: account, inbox: inbox, scheduled_at: scheduled_at)
      create(:conversation, account: account, inbox: inbox, contact: contact, campaign: other)
      other
    end

    it 'descarta quem so tem o carimbo na conversa, sem linha em campaign_recipients' do
      dispatched_by_old_engine!

      expect(CampaignRecipient.count).to be_zero
      expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
    end

    it 'nao descarta pelo carimbo da PROPRIA campanha' do
      create(:conversation, account: account, inbox: inbox, contact: contact, campaign: campaign)

      expect(build_audience.accepted.size).to eq(1)
    end

    it 'encontra o carimbo mesmo quando a ficha nasceu sem o 9o digito' do
      contact.update!(phone_number: '+556692927211')
      dispatched_by_old_engine!

      expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
    end
  end

  describe 'corte da dedup (dispatch_config["dedup"])' do
    let!(:contact) { create(:contact, account: account, phone_number: phone) }

    def dedup!(config)
      campaign.update!(dispatch_config: (campaign.dispatch_config || {}).merge('dedup' => config))
    end

    def dispatched_by_old_engine!(scheduled_at: Time.current)
      other = create(:campaign, account: account, inbox: inbox, scheduled_at: scheduled_at)
      create(:conversation, account: account, inbox: inbox, contact: contact, campaign: other)
      other
    end

    describe 'window_days' do
      it 'ignora disparo mais antigo que a janela' do
        dispatched_by_old_engine!(scheduled_at: 200.days.ago)
        dedup!('window_days' => 90)

        expect(build_audience.accepted.size).to eq(1)
      end

      it 'mantem o descarte de disparo dentro da janela' do
        dispatched_by_old_engine!(scheduled_at: 10.days.ago)
        dedup!('window_days' => 90)

        expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
      end

      # A janela do motor novo se apoia no `sent_at`, com fallback pro `created_at`.
      it 'aplica a janela tambem ao motor novo' do
        other = create(:campaign, account: account, inbox: inbox)
        CampaignRecipient.create!(campaign: other, account: account, phone_number: phone,
                                  canonical_phone: canonical, status: :sent, sent_at: 200.days.ago)
        dedup!('window_days' => 90)

        expect(build_audience.accepted.size).to eq(1)
      end
    end

    describe 'campaign_ids' do
      it 'descarta quando o disparo veio de uma campanha listada' do
        outra = dispatched_by_old_engine!
        dedup!('campaign_ids' => [outra.id])

        expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
      end

      it 'ignora disparo de campanha fora da lista' do
        dispatched_by_old_engine!
        dedup!('campaign_ids' => [campaign.id + 10_000])

        expect(build_audience.accepted.size).to eq(1)
      end
    end

    describe 'sources' do
      it 'com sources=recipients, ignora o carimbo da conversa' do
        dispatched_by_old_engine!
        dedup!('sources' => ['recipients'])

        expect(build_audience.accepted.size).to eq(1)
      end

      it 'com sources=conversations, ignora campaign_recipients' do
        already_dispatched!
        dedup!('sources' => ['conversations'])

        expect(build_audience.accepted.size).to eq(1)
      end

      # Config com nome errado nao pode virar disparo em dobro: cai no corte mais largo.
      it 'trata source desconhecido como ausente e roda os dois motores' do
        dispatched_by_old_engine!
        dedup!('sources' => ['inexistente'])

        expect(build_audience.rejected.first[:reason]).to eq('ja_disparado')
      end
    end
  end

  describe 'fail-open' do
    it 'aceita numero que nao tem ficha na base' do
      result = build_audience

      expect(Contact.find_by(phone_number: phone)).to be_nil
      expect(result.rejected).to be_empty
      expect(result.accepted.size).to eq(1)
    end
  end

  describe 'stats' do
    it 'contabiliza optou_por_sair em por_motivo' do
      suppress!(create(:contact, account: account, phone_number: phone))
      list = rows + [{ name: 'Fixo', phone: '+556632114876' }]

      stats = build_audience(list).stats

      expect(stats[:total]).to eq(2)
      expect(stats[:aceitos]).to eq(0)
      expect(stats[:descartados]).to eq(2)
      expect(stats[:por_motivo]).to eq('telefone_fixo' => 1, 'optou_por_sair' => 1)
    end
  end
end
