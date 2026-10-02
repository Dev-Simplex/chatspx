require 'rails_helper'

RSpec.describe Captain::Tools::ConsultarHistoricoConversaTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:atendente) { create(:user, account: account, display_name: 'Atendente') }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  def mensagem(tipo, instante, conteudo, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: tipo, content: conteudo, created_at: instante, **attrs)
  end

  # REGRA #1: exemplo na descrição vira texto que o modelo copia.
  it 'describes the tool without a copyable example' do
    expect(described_class.description).not_to match(/\bex(emplo)?[.:]/i)
    expect(tool.parameters.values.map(&:description).join).not_to match(/\bex(emplo)?[.:]/i)
  end

  context 'when the AI took over after a human attendance' do
    before do
      mensagem(:incoming, 1.day.ago, 'quero saber da vistoria da casa')
      mensagem(:outgoing, 1.day.ago + 1.minute, 'vistoria marcada para amanhã', sender: atendente)
      mensagem(:incoming, 10.minutes.ago, 'e a vistoria?')
      Captain::AssistantLog.create!(captain_assistant: assistant, conversation_id: conversation.id,
                                    event_type: 'mirror_assigned', created_at: 9.minutes.ago)
    end

    it 'returns only messages from before the takeover, with date and origin' do
      resultado = tool.perform(tool_context, assunto: 'vistoria')

      expect(resultado).to include('contato: quero saber da vistoria da casa')
      expect(resultado).to include('atendente Atendente: vistoria marcada para amanhã')
      expect(resultado).not_to include('e a vistoria?')
    end

    it 'confirms the absence when nothing before matches' do
      expect(tool.perform(tool_context, assunto: 'boleto')).to eq('Nenhuma mensagem anterior fala desse assunto.')
    end
  end

  it 'says there is nothing before when the AI never took over' do
    mensagem(:incoming, 1.hour.ago, 'oi')

    expect(tool.perform(tool_context, assunto: 'qualquer')).to eq('Esta conversa não tem mensagens de antes de você assumir.')
  end
end
