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
