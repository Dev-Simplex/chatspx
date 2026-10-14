# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannels::AutoAlertsService do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:channel) { create(:internal_channel, account: account, team: team, channel_type: :team, name: team.name) }
  let(:consultor) { create(:user, account: account, name: 'Gelson de Paula') }

  def enable(*events)
    channel.update!(settings: { 'auto_alerts' => events.index_with(true) })
  end

  describe 'lead parado' do
    let(:conversation) { create(:conversation, account: account, team: team) }
    let!(:log) { create(:distribuicao_log, :aberta, conversation: conversation, chosen_user: consultor) }

    it 'não avisa com o aviso desligado (padrão)' do
      expect { described_class.new(channel).perform }.not_to change(InternalMessage, :count)
    end

    it 'avisa uma vez por lead e ciclo, com o cartão da conversa' do
      enable('lead_parado')
      2.times { described_class.new(channel).perform }

      expect(channel.messages.count).to eq(1)
      message = channel.messages.last
      expect(message).to be_message_type_system
      expect(message.user_id).to be_nil
      expect(message.shared_conversation_id).to eq(conversation.id)
      expect(message.content).to include('Gelson de Paula', "##{conversation.display_id}")
    end

    it 'avisa de novo quando o lead é designado outra vez (novo ciclo)' do
      enable('lead_parado')
      described_class.new(channel).perform
      log.update!(designado_em: 35.minutes.ago)
      described_class.new(channel).perform

      expect(channel.messages.count).to eq(2)
    end

    it 'ignora lead de outro time' do
      enable('lead_parado')
      conversation.update!(team: create(:team, account: account))

      expect { described_class.new(channel).perform }.not_to change(InternalMessage, :count)
    end
  end

  describe 'meta batida' do
    let(:rows) do
      [{ id: consultor.id, name: 'Emily Santos',
         metrics: { 'resolved_conversations' => { actual: 12, goal: 10.0, attainment: 1.2 },
                    'nps' => { actual: 50, goal: 70.0, attainment: 0.71 } } }]
    end

    before do
      ranking = instance_double(PerformanceGoals::RankingService, perform: { rows: rows })
      allow(PerformanceGoals::RankingService).to receive(:new).and_return(ranking)
      enable('meta_batida')
    end

    it 'avisa uma vez por pessoa, indicador e mês, só da meta atingida' do
      2.times { described_class.new(channel).perform }

      expect(channel.messages.pluck(:content)).to eq(['Emily Santos bateu a meta do mês: 12 de 10 conversas resolvidas'])
    end

    it 'junta num aviso só as metas que a pessoa bate de uma vez e avisa depois só da nova' do
      rows.first[:metrics]['nps'] = { actual: 80, goal: 70.0, attainment: 1.14 }
      described_class.new(channel).perform
      rows.first[:metrics]['kanban_wins'] = { actual: 5, goal: 4.0, attainment: 1.25 }
      described_class.new(channel).perform

      expect(channel.messages.order(:id).pluck(:content)).to eq(
        ['Emily Santos bateu 2 metas do mês: 12 de 10 conversas resolvidas; NPS 80 (meta: 70)',
         'Emily Santos bateu a meta do mês: 5 de 4 negócios ganhos']
      )
    end

    it 'não repete a meta já avisada no formato antigo, de uma chave só' do
      month = PerformanceGoals::Month.current(account).strftime('%Y-%m')
      channel.messages.create!(message_type: :system, content: 'antigo',
                               content_attributes: { 'alert' => { 'key' => "meta_batida:#{consultor.id}:resolved_conversations:#{month}" } })

      expect { described_class.new(channel).perform }.not_to change(InternalMessage, :count)
    end

    it 'avisa de novo no mês seguinte' do
      described_class.new(channel).perform
      travel_to(1.month.from_now) { described_class.new(channel).perform }

      expect(channel.messages.count).to eq(2)
    end
  end

  describe '.can_manage?' do
    it 'libera admin da conta e supervisor do time; barra agente e supervisor de outro time' do
      admin = create(:user, account: account, role: :administrator)
      agent = create(:user, account: account, role: :agent)
      supervisor = create(:user, account: account, role: :administrator)
      create(:team_supervisor, team: team, user: supervisor)
      other_supervisor = create(:user, account: account, role: :administrator)
      create(:team_supervisor, team: create(:team, account: account), user: other_supervisor)

      allowed = [admin, agent, supervisor, other_supervisor].map do |user|
        described_class.can_manage?(channel, account.account_users.find_by(user: user))
      end
      expect(allowed).to eq([true, false, true, false])
    end
  end
end
