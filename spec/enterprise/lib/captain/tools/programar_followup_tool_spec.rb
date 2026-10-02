require 'rails_helper'

RSpec.describe Captain::Tools::ProgramarFollowupTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'tools' => ['programar_followup'] }) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  before do
    allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
    travel_to Time.zone.local(2026, 9, 29, 15, 0)
  end

  it 'programa a cutucada no momento que o cliente disse na janela' do
    expect do
      tool.perform(tool_context, minutos: 30, motivo: 'retomar a visita', janela: 'hoje às 21h30')
    end.to have_enqueued_job(Captain::Conversation::FollowupJob).at(Time.zone.local(2026, 9, 29, 21, 30))

    expect(conversation.reload.custom_attributes['followup_janela']).to eq('hoje às 21h30')
  end

  it 'sem janela, usa os minutos que o agente escolheu' do
    expect do
      tool.perform(tool_context, minutos: 30, motivo: 'retomar a visita')
    end.to have_enqueued_job(Captain::Conversation::FollowupJob).at(30.minutes.from_now)
  end

  context 'with the agendada on in the agent' do
    before { assistant.update!(config: { 'tools' => %w[programar_followup agendar_mensagem] }) }

    it 'não programa a cutucada com janela e aponta a agendada' do
      resposta = nil
      expect do
        resposta = tool.perform(tool_context, minutos: 30, motivo: 'retomar a visita', janela: 'hoje às 21h30')
      end.not_to have_enqueued_job(Captain::Conversation::FollowupJob)

      expect(resposta).to include('agendar_mensagem')
      expect(conversation.reload.custom_attributes['followup_token']).to be_nil
    end

    it 'segue programando a cutucada sem janela' do
      expect do
        tool.perform(tool_context, minutos: 30, motivo: 'retomar a visita')
      end.to have_enqueued_job(Captain::Conversation::FollowupJob)
    end
  end
end
