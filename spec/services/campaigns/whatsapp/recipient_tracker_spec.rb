# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::Whatsapp::RecipientTracker do
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:aniversario) { create(:campaign, account: account, inbox: inbox, template_name: 'aniversario') }
  let(:exame) { create(:campaign, account: account, inbox: inbox, template_name: 'exame') }

  def template_message(campaign, at: 1.hour.ago, status: :sent)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     status: status, created_at: at, updated_at: at,
                     additional_attributes: { 'template_params' => { 'name' => campaign.template_name } })
  end

  def recipient(campaign, sent_at:, message: nil, status: :sent)
    CampaignRecipient.create!(campaign: campaign, account: account, contact: contact, conversation: conversation,
                              phone_number: '+5566999990000', status: status, sent_at: sent_at, message_id: message&.id)
  end

  def incoming(at:)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: contact, created_at: at)
  end

  describe '.message_status' do
    it 'leva entregue e lido ao destinatário daquela mensagem, e só a ele' do
      mensagem = template_message(aniversario)
      dono = recipient(aniversario, sent_at: 1.hour.ago, message: mensagem)
      outro = recipient(exame, sent_at: 1.hour.ago, message: template_message(exame))

      mensagem.update!(status: :delivered)
      described_class.message_status(mensagem)
      expect(dono.reload).to be_delivered
      expect(dono.delivered_at).to be_present

      mensagem.update!(status: :read)
      described_class.message_status(mensagem)
      expect(dono.reload).to be_read
      expect(dono.read_at).to be_present
      expect(outro.reload).to be_sent
    end

    # Webhooks chegam fora de ordem: o `delivered` atrasado não pode desfazer o `read`.
    it 'não regride quando o entregue chega depois do lido' do
      mensagem = template_message(aniversario, status: :read)
      dono = recipient(aniversario, sent_at: 1.hour.ago, message: mensagem)
      described_class.message_status(mensagem)

      mensagem.update!(status: :delivered)
      described_class.message_status(mensagem)

      expect(dono.reload).to be_read
      expect(dono.delivered_at).to be_present
    end

    it 'grava a falha com o código da Meta' do
      mensagem = template_message(aniversario)
      dono = recipient(aniversario, sent_at: 1.hour.ago, message: mensagem)

      mensagem.update!(status: :failed, external_error: '131026: Message undeliverable')
      described_class.message_status(mensagem)

      expect(dono.reload).to be_failed
      expect(dono.failed_at).to be_present
      expect(dono.external_error).to eq('131026: Message undeliverable')
    end
  end

  describe '.reply' do
    it 'não conta mensagem recebida antes do envio' do
      dono = recipient(aniversario, sent_at: 1.hour.ago)

      described_class.reply(incoming(at: 2.hours.ago))

      expect(dono.reload).to be_sent
      expect(dono.replied_at).to be_nil
    end

    it 'conta a primeira mensagem recebida depois do envio' do
      dono = recipient(aniversario, sent_at: 1.hour.ago)
      primeira = incoming(at: 30.minutes.ago)

      described_class.reply(primeira)
      described_class.reply(incoming(at: 10.minutes.ago))

      expect(dono.reload).to be_replied
      expect(dono.replied_at).to be_within(1.second).of(primeira.created_at)
    end

    # O contato recebeu duas campanhas: a resposta é ao último template, não à campanha de
    # origem da conversa.
    it 'atribui a resposta só ao disparo mais recente antes dela' do
      antigo = recipient(aniversario, sent_at: 10.days.ago)
      recente = recipient(exame, sent_at: 1.hour.ago)

      described_class.reply(incoming(at: 30.minutes.ago))

      expect(recente.reload).to be_replied
      expect(antigo.reload).to be_sent
    end

    it 'mantém respondido quando o lido chega depois, mas grava o carimbo do lido' do
      mensagem = template_message(aniversario)
      dono = recipient(aniversario, sent_at: 1.hour.ago, message: mensagem)
      described_class.reply(incoming(at: 30.minutes.ago))

      mensagem.update!(status: :read)
      described_class.message_status(mensagem)

      expect(dono.reload).to be_replied
      expect(dono.read_at).to be_present
    end
  end

  describe '.pricing' do
    it 'grava categoria e se é cobrável, e nada além do que a Meta define' do
      mensagem = template_message(aniversario)
      dono = recipient(aniversario, sent_at: 1.hour.ago, message: mensagem)

      described_class.pricing(mensagem, { 'billable' => true, 'pricing_model' => 'PMP', 'category' => 'marketing',
                                          'type' => 'regular', 'intruso' => 'x' })

      expect(dono.reload.pricing).to eq('billable' => true, 'pricing_model' => 'PMP', 'category' => 'marketing',
                                        'type' => 'regular')
    end
  end

  describe '.backfill' do
    it 'acha a mensagem do template de quem foi enviado antes do rastreio e reaplica status e resposta' do
      sent_at = 1.hour.ago
      mensagem = template_message(aniversario, at: sent_at - 2.seconds, status: :read)
      dono = recipient(aniversario, sent_at: sent_at)
      incoming(at: 30.minutes.ago)

      described_class.backfill(dono)

      dono.reload
      expect(dono.message_id).to eq(mensagem.id)
      expect(dono.read_at).to be_present
      expect(dono).to be_replied
    end
  end
end
