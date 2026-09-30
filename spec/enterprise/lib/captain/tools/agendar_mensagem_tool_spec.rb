require 'rails_helper'

RSpec.describe Captain::Tools::AgendarMensagemTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  before { travel_to Time.zone.local(2026, 9, 29, 15, 0) }

  def pendentes
    ScheduledMessage.pending.where(conversation_id: conversation.id)
  end

  describe 'agendar' do
    it 'grava a mensagem pronta para o momento que o cliente disse, em nome do agente' do
      expect do
        tool.perform(tool_context, acao: 'agendar', quando: 'hoje às 20h', texto: 'Conseguiu conversar?')
      end.to have_enqueued_job(ScheduledMessages::SendJob)

      agendada = pendentes.sole
      expect(agendada.message).to eq('Conseguiu conversar?')
      expect(agendada.scheduled_at).to eq(Time.zone.local(2026, 9, 29, 20, 0))
      expect(agendada.captain_assistant_id).to eq(assistant.id)
    end

    it 'agendar de novo substitui a anterior, com texto e momento novos' do
      tool.perform(tool_context, acao: 'agendar', quando: 'às 20h', texto: 'Primeira versão')
      tool.perform(tool_context, acao: 'agendar', quando: 'às 22h30', texto: 'Segunda versão')

      expect(pendentes.pluck(:message, :scheduled_at)).to eq([['Segunda versão', Time.zone.local(2026, 9, 29, 22, 30)]])
      expect(ScheduledMessage.where(conversation_id: conversation.id).cancelled.count).to eq(1)
    end

    it 'não mexe em agendada criada por pessoa' do
      humana = ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Do time',
                                        scheduled_at: 1.day.from_now, status: :pending)

      tool.perform(tool_context, acao: 'agendar', quando: 'às 20h', texto: 'Da IA')

      expect(humana.reload).to be_pending
    end

    it 'não agenda quando não entende o momento, e diz isso ao agente' do
      resposta = tool.perform(tool_context, acao: 'agendar', quando: 'quando der', texto: 'Oi')

      expect(pendentes).to be_empty
      expect(resposta).to include('NÃO agendei')
    end

    it 'não agenda além do teto de dias' do
      tool.perform(tool_context, acao: 'agendar', quando: 'semana que vem às 18h', texto: 'Oi')
      expect(pendentes).to be_empty
    end

    it 'exige o texto' do
      tool.perform(tool_context, acao: 'agendar', quando: 'às 20h', texto: '')
      expect(pendentes).to be_empty
    end
  end

  describe 'cancelar' do
    it 'cancela a agendada da IA' do
      tool.perform(tool_context, acao: 'agendar', quando: 'às 20h', texto: 'Oi')

      expect(tool.perform(tool_context, acao: 'cancelar')).to eq('Mensagem agendada cancelada.')
      expect(pendentes).to be_empty
    end

    it 'avisa quando não há o que cancelar' do
      expect(tool.perform(tool_context, acao: 'cancelar')).to eq('Não havia mensagem agendada para cancelar.')
    end
  end
end
