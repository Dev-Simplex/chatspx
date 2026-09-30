# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campaigns::Whatsapp::DispatchSchedulerJob do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  # Canal montado a mão: a trait :whatsapp do factory cria 360dialog e bate na rede.
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:dispatcher) { instance_double(Campaigns::Whatsapp::RecipientDispatchService, perform: true) }

  def scheduled_campaign(scheduled_at:, **attrs)
    campaign = create(:campaign, account: account, inbox: inbox, template_name: 'aniversario_v2',
                                 target_team_id: team.id, scheduled_at: scheduled_at, **attrs)
    campaign.dispatch_scheduled!
    campaign
  end

  def add_recipient(campaign)
    CampaignRecipient.create!(campaign: campaign, account: account, phone_number: '+5566992927211')
  end

  before do
    allow(Campaigns::Whatsapp::RecipientDispatchService).to receive(:new).and_return(dispatcher)
  end

  describe 'promoção do agendamento' do
    it 'inicia a campanha agendada cujo horário já passou, no mesmo ciclo' do
      campaign = scheduled_campaign(scheduled_at: 5.minutes.ago)
      add_recipient(campaign)

      described_class.perform_now

      expect(campaign.reload).to be_dispatch_running
      expect(Campaigns::Whatsapp::RecipientDispatchService).to have_received(:new).once
    end

    it 'não inicia a campanha agendada para o futuro' do
      campaign = scheduled_campaign(scheduled_at: 1.hour.from_now)
      add_recipient(campaign)

      described_class.perform_now

      expect(campaign.reload).to be_dispatch_scheduled
      expect(Campaigns::Whatsapp::RecipientDispatchService).not_to have_received(:new)
    end

    it 'não inicia sem destinatários e grava o motivo que o painel mostra' do
      campaign = scheduled_campaign(scheduled_at: 5.minutes.ago)

      described_class.perform_now

      campaign.reload
      expect(campaign).to be_dispatch_failed
      expect(campaign.dispatch_config['start_error']).to eq('Campanha sem destinatários')
    end

    it 'não inicia sem time e grava o motivo' do
      campaign = scheduled_campaign(scheduled_at: 5.minutes.ago, target_team_id: nil)
      add_recipient(campaign)

      described_class.perform_now

      campaign.reload
      expect(campaign).to be_dispatch_failed
      expect(campaign.dispatch_config['start_error']).to eq('Defina o time que recebe as conversas')
      expect(Campaigns::Whatsapp::RecipientDispatchService).not_to have_received(:new)
    end

    it 'não inicia sem template e grava o motivo' do
      campaign = scheduled_campaign(scheduled_at: 5.minutes.ago)
      campaign.update!(template_name: nil, template_params: {})
      add_recipient(campaign)

      described_class.perform_now

      campaign.reload
      expect(campaign).to be_dispatch_failed
      expect(campaign.dispatch_config['start_error']).to eq('Defina o template do disparo')
    end

    it 'preserva o resto do dispatch_config ao gravar o motivo' do
      campaign = scheduled_campaign(scheduled_at: 5.minutes.ago, dispatch_config: { 'health_gate' => false })

      described_class.perform_now

      expect(campaign.reload.dispatch_config).to include('health_gate' => false, 'start_error' => 'Campanha sem destinatários')
    end
  end
end
