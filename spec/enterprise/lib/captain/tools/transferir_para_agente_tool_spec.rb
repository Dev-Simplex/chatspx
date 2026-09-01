require 'rails_helper'

RSpec.describe Captain::Tools::TransferirParaAgenteTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Bruna Vendas') }
  let(:target_assistant) { create(:captain_assistant, account: account, name: 'Leo Locação', description: 'Especialista em locação') }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  # O espelho nasce por after_commit no assistant; forçamos aqui para o teste não
  # depender da ordem dos callbacks — em produção ele sempre existe.
  before { target_assistant.mirror_agent_bot }

  describe '#description' do
    # Gatilho POSITIVO e silêncio: a transferência é invisível pro cliente (DC-7).
    it 'describes the transfer and states it is invisible to the customer' do
      expect(tool.description).to include('Transfere a conversa para outro agente de IA')
      expect(tool.description).to include('invisível')
    end
  end

  describe '#parameters' do
    it 'takes the target agent by name, and nothing else' do
      expect(tool.parameters[:agente].type).to eq('string')
      expect(tool.parameters[:agente].required).to be true
      expect(tool.parameters.keys).to contain_exactly(:agente)
    end
  end

  describe '#perform' do
    context 'when the target exists and is operational' do
      it 'swaps the mirror owner and tells the old agent to go silent' do
        result = tool.perform(tool_context, agente: 'Leo Locação')

        expect(result).to include('Conversa transferida para Leo Locação')
        expect(result).to include('NÃO envie mais nenhuma resposta')
        expect(conversation.reload.assignee_agent_bot).to eq(target_assistant.agent_bot)
      end

      # O LLM escreve o nome como aparece na conduta dele, que nem sempre bate em
      # caixa e acentuação com o cadastro.
      it 'resolves the name ignoring case and accents' do
        tool.perform(tool_context, agente: '  leo locacao ')

        expect(conversation.reload.assignee_agent_bot).to eq(target_assistant.agent_bot)
      end

      it 'kicks the new agent through the AssignmentKickJob (DC-7)' do
        expect do
          tool.perform(tool_context, agente: 'Leo Locação')
        end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
      end

      it 'creates no message at all — the handover is silent (DC-7)' do
        expect do
          tool.perform(tool_context, agente: 'Leo Locação')
        end.not_to change(Message, :count)
      end

      it 'moves the conversation to the target agent team' do
        team = create(:team, account: account)
        target_assistant.update!(config: { 'team_id' => team.id })

        tool.perform(tool_context, agente: 'Leo Locação')

        expect(conversation.reload.team_id).to eq(team.id)
      end

      it 'records the handover in the history the guard reads next time' do
        tool.perform(tool_context, agente: 'Leo Locação')

        historico = conversation.reload.custom_attributes['ia_transferencias']
        expect(historico.last).to include('de' => assistant.id, 'para' => target_assistant.id)
        expect(historico.last['t']).to be_present
      end
    end

    context 'when there is nothing to do' do
      it 'refuses when the conversation is already with the target agent' do
        conversation.update!(assignee_agent_bot: target_assistant.agent_bot)

        expect(tool.perform(tool_context, agente: 'Leo Locação')).to eq('A conversa já está com este agente.')
      end

      it 'refuses a name that does not exist in the team' do
        expect(tool.perform(tool_context, agente: 'Fulano')).to eq('Não encontrei o agente Fulano na equipe.')
      end

      it 'refuses an agent from another account' do
        create(:captain_assistant, name: 'Externo Alheio')

        expect(tool.perform(tool_context, agente: 'Externo Alheio')).to eq('Não encontrei o agente Externo Alheio na equipe.')
      end

      # Sem espelho o agente não está operacional. A tool NÃO cria o espelho de
      # propósito: transferir para quem não opera deixaria a conversa órfã.
      it 'refuses when the target agent has no mirror' do
        target_assistant.agent_bot.destroy!
        target_assistant.reload

        expect(tool.perform(tool_context, agente: 'Leo Locação')).to eq('O agente Leo Locação está indisponível no momento.')
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'refuses when it cannot identify the conversation' do
        contexto = Struct.new(:state).new({ conversation: { id: 999_999 } })

        expect(tool.perform(contexto, agente: 'Leo Locação')).to eq('Não consegui identificar a conversa.')
      end
    end

    # Trilho anti-ping-pong: conv 17770 (24/07) quicou Júlia<->Bruna três vezes em três
    # minutos até um humano quebrar o loop na mão.
    context 'with the anti-ping-pong guard' do
      def historico(entradas)
        conversation.update!(custom_attributes: { 'ia_transferencias' => entradas })
      end

      it 'blocks handing back to whoever already took part in the recent bouncing' do
        historico([{ 'de' => target_assistant.id, 'para' => assistant.id, 't' => 10.minutes.ago.iso8601 }])

        result = tool.perform(tool_context, agente: 'Leo Locação')

        expect(result).to include('NÃO transferi')
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'blocks when the transfer cap in the window is exceeded, even for a fresh target' do
        outros = create_list(:captain_assistant, 3, account: account)
        historico(outros.map { |o| { 'de' => assistant.id, 'para' => o.id, 't' => 5.minutes.ago.iso8601 } })

        expect(tool.perform(tool_context, agente: 'Leo Locação')).to include('NÃO transferi')
      end

      it 'calls a human when it blocks — the customer cannot stay stuck in the bouncing' do
        historico([{ 'de' => target_assistant.id, 'para' => assistant.id, 't' => 10.minutes.ago.iso8601 }])
        handoff = instance_double(Captain::Conversation::HumanHandoffService, perform: true)
        allow(Captain::Conversation::HumanHandoffService).to receive(:new).and_return(handoff)

        tool.perform(tool_context, agente: 'Leo Locação')

        expect(handoff).to have_received(:perform)
      end

      # A janela é curta de propósito: com conversa única por contato o assunto muda
      # legitimamente ao longo de meses, e contar a conversa inteira travaria a troca.
      it 'ignores old handovers, outside the window' do
        historico([{ 'de' => target_assistant.id, 'para' => assistant.id, 't' => 3.hours.ago.iso8601 }])

        expect(tool.perform(tool_context, agente: 'Leo Locação')).to include('Conversa transferida')
      end

      it 'does not let a corrupted history bring the service down' do
        historico(['lixo', { 'sem' => 'timestamp' }])

        expect(tool.perform(tool_context, agente: 'Leo Locação')).to include('Conversa transferida')
      end
    end
  end

  describe 'registry (tools.yml + resolução por convenção)' do
    it 'is registered as a built-in agent tool' do
      tool_ids = Captain::Assistant.built_in_tool_ids
      expect(tool_ids).to include('transferir_para_agente')
    end

    it 'resolves the class from the snake_case id' do
      expect(Captain::Assistant.resolve_tool_class('transferir_para_agente')).to eq(described_class)
    end
  end

  describe '#active?' do
    it 'returns true for public tools' do
      expect(tool.active?).to be true
    end
  end
end
