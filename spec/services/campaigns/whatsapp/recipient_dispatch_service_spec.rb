# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::Whatsapp::RecipientDispatchService do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  # Canal montado a mão: a trait :whatsapp do factory cria 360dialog e bate na rede.
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, template_name: 'aniversario_v2', target_team_id: team.id)
  end
  let(:sender) { instance_double(Whatsapp::SendTemplateService, perform: true) }

  before { allow(Whatsapp::SendTemplateService).to receive(:new).and_return(sender) }

  def dispatch(phone)
    recipient = CampaignRecipient.create!(campaign: campaign, account: account, phone_number: phone, status: :processing)
    described_class.new(recipient: recipient).perform
    recipient.reload
  end

  # Caso real: disparo da Fábrica em 25/09 — 34 dos 36 primeiros contatos NOVOS morreram em
  # "Phone number deve estar no formato e164" porque a carga entrou sem o `+`.
  it 'cria o contato novo em E.164 quando o telefone foi gravado sem +' do
    recipient = dispatch('5566992927211')

    expect(recipient).to be_sent
    expect(recipient.contact.phone_number).to eq('+5566992927211')
  end

  it 'completa o DDI do número brasileiro gravado só com DDD' do
    recipient = dispatch('66992927211')

    expect(recipient).to be_sent
    expect(recipient.contact.phone_number).to eq('+5566992927211')
  end

  it 'mantém o número que já veio em E.164' do
    recipient = dispatch('+5566992927211')

    expect(recipient).to be_sent
    expect(recipient.contact.phone_number).to eq('+5566992927211')
  end
end
