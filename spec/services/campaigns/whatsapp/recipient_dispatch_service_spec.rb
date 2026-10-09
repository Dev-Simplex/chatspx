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
  let(:sender) { instance_double(Whatsapp::SendTemplateService, perform: nil) }

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

  # É pela mensagem do template que entregue, lido e falhou chegam ao destinatário.
  it 'liga o destinatário à mensagem do template enviada' do
    message = create(:message, account: account, inbox: inbox, message_type: :outgoing)
    allow(sender).to receive(:perform).and_return(message)

    recipient = dispatch('+5566992927211')

    expect(recipient).to be_sent
    expect(recipient.message_id).to eq(message.id)
  end

  # O motivo do bloqueio vai como código estável: é ele que a lista de não enviados traduz.
  it 'grava o motivo quando a caixa virou somente leitura' do
    campaign # nasce antes: a caixa vira somente leitura no meio do disparo
    inbox.update!(read_only: true)

    recipient = dispatch('+5566992927211')

    expect(recipient).to be_skipped
    expect(recipient.external_error).to eq('caixa_somente_leitura')
    expect(recipient.reason_code).to eq('caixa_somente_leitura')
  end

  it 'grava o motivo quando o contato já está em atendimento' do
    contact = create(:contact, account: account, phone_number: '+5566992927211')
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566992927211')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)

    recipient = dispatch('+5566992927211')

    expect(recipient).to be_skipped
    expect(recipient.external_error).to eq('atendimento_ativo')
    expect(recipient.contact_id).to eq(contact.id)
  end

  it 'grava a falha do envio para a lista de não enviados' do
    allow(sender).to receive(:perform).and_raise(StandardError, 'boom')

    recipient = dispatch('+5566992927211')

    expect(recipient).to be_failed
    expect(recipient.reason_code).to eq('erro_envio')
  end
end
