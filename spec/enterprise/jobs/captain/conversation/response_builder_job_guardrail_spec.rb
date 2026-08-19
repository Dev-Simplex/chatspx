require 'rails_helper'

# 6.01 — o guardrail LIGADO no caminho de envio.
#
# NENHUMA IA É CHAMADA AQUI. O gerador de resposta é um dublê (`instance_double`) que
# devolve a string que o exemplo quiser e, quando o caso pede, empurra uma tool call
# para a janela em memória — que é exatamente o que a ferramenta real faria ao rodar
# dentro da geração.
RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :pending,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:mock_llm_chat_service) { instance_double(Captain::Llm::AssistantChatService) }
  let(:mock_action_classifier_service) { instance_double(Captain::Llm::AssistantActionClassifierService) }
  let(:mock_false_promise_service) { instance_double(Captain::Llm::AssistantFalsePromiseService) }
  let(:negativa) { 'Não encontrei imóveis com esse perfil.' }
  let(:handoff_message) { I18n.t('conversations.captain.handoff', locale: account.locale) }

  # O dublê do gerador: responde `content` e, se `tool` vier, marca na janela que uma
  # ferramenta rodou e devolveu resultado durante a geração desta resposta.
  def stub_generation(content, tool: nil)
    allow(mock_llm_chat_service).to receive(:generate_response) do
      Captain::ToolTraceWindow.record(**tool) if tool
      { 'response' => content }
    end
  end

  before do
    create(:message, conversation: conversation, content: 'Tem casa de 3 quartos?', message_type: :incoming)

    allow(inbox).to receive(:captain_active?).and_return(true)
    allow(account).to receive(:feature_enabled?).and_return(false)
    allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(mock_llm_chat_service)
    allow(Captain::Llm::AssistantActionClassifierService).to receive(:new).and_return(mock_action_classifier_service)
    allow(mock_action_classifier_service).to receive(:classify).and_return({ 'action' => 'continue' })
    allow(Captain::Llm::AssistantFalsePromiseService).to receive(:new).and_return(mock_false_promise_service)
    allow(mock_false_promise_service).to receive(:detect).and_return({ 'decision' => 'safe', 'reason' => 'safe_response' })
  end

  describe 'a resposta que nega o que a ferramenta devolveu' do
    before { stub_generation(negativa, tool: { tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A, Casa B' }) }

    it 'never reaches the visitor' do
      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).not_to include(negativa)
    end

    it 'turns into a handoff, not into silence' do
      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).to include(handoff_message)
      expect(conversation.reload.status).to eq('open')
      expect(conversation.waiting_since).to be_present
    end

    it 'registers the reason, naming the tool' do
      described_class.perform_now(conversation, assistant)

      log = Captain::AssistantLog.find_by(conversation: conversation, event_type: 'guardrail_retained')
      expect(log).to be_present
      expect(log.payload['motivo']).to include('buscar_imovel')
      expect(log.payload['findings'].first['categoria']).to eq('contradisse_tool')
    end

    it 'does not charge a response that was never sent' do
      described_class.perform_now(conversation, assistant)

      account.reload
      expect(account.usage_limits[:captain][:responses][:consumed]).to eq(0)
    end
  end

  # O aceite pede a diferença MEDIDA, não afirmada: o mesmo caso, com e sem o gate de
  # pré-envio. Sem ele, a mensagem sai e o flagra só existe DEPOIS, no eval.
  describe 'o mesmo caso nos dois modos' do
    before { stub_generation(negativa, tool: { tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A, Casa B' }) }

    it 'sends the false denial when the pre-send gate is absent (o comportamento de hoje)' do
      passing = Captain::ResponseGuardrailService::Result.new(findings: [])
      sem_gate = instance_double(Captain::ResponseGuardrailService, perform: passing)
      allow(Captain::ResponseGuardrailService).to receive(:new).and_return(sem_gate)

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).to include(negativa)
      expect(Captain::AssistantLog.where(conversation: conversation, event_type: 'guardrail_retained')).to be_empty

      # E o pós-fato, aí sim, ANOTA — depois de o visitante já ter lido.
      enviada = conversation.messages.outgoing.find_by(content: negativa)
      Captain::ToolCall.create!(account_id: account.id, conversation_id: conversation.id,
                                captain_assistant_id: assistant.id, tool_name: 'buscar_imovel',
                                result_preview: 'Casa A, Casa B', status: 'ok', created_at: enviada.created_at - 1.second)
      episode = Captain::ConversationEpisode.create!(
        account_id: account.id, conversation_id: conversation.id, seq: 1,
        first_message_id: conversation.messages.first.id, last_message_id: enviada.id,
        started_at: enviada.created_at - 10.minutes, last_message_at: enviada.created_at,
        ended_at: enviada.created_at, boundary_reason: 'resolve', mensagens: conversation.messages.count
      )

      findings = Captain::EpisodeGateService.new(episode: episode).perform
      expect(findings.map { |f| f['categoria'] }).to include('contradisse_tool')
      expect(findings.first['message_id']).to eq(enviada.id)
    end

    it 'retains the same text with the gate in place' do
      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).not_to include(negativa)
    end
  end

  describe 'o que o guardrail NÃO impede' do
    it 'lets an affirmative answer through' do
      stub_generation('Encontrei 3 opções de 3 quartos: A, B e C.',
                      tool: { tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A, Casa B' })

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).to include('Encontrei 3 opções de 3 quartos: A, B e C.')
      expect(conversation.reload.status).to eq('pending')
    end

    it 'lets a denial through when no tool contradicts it' do
      stub_generation(negativa)

      described_class.perform_now(conversation, assistant)

      expect(conversation.messages.outgoing.pluck(:content)).to include(negativa)
    end
  end

  # Falha do guardrail NUNCA derruba o atendimento — em erro, libera e registra.
  # Mesma regra do rescue de episode_eval_job.rb:37-38.
  describe 'quando o próprio guardrail quebra' do
    before do
      stub_generation(negativa, tool: { tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A, Casa B' })
      allow(Captain::ResponseGuardrailService).to receive(:new).and_raise(StandardError, 'boom')
    end

    it 'still answers the visitor' do
      expect { described_class.perform_now(conversation, assistant) }.not_to raise_error

      expect(conversation.messages.outgoing.pluck(:content)).to include(negativa)
    end

    it 'leaves the failure in the log' do
      allow(Rails.logger).to receive(:warn)

      described_class.perform_now(conversation, assistant)

      expect(Rails.logger).to have_received(:warn).with(/guardrail.*boom/i)
    end
  end

  describe 'a janela de tool calls' do
    it 'is closed after the job, so nothing leaks into the next response on this thread' do
      stub_generation('Tudo certo por aqui, posso te ajudar em mais alguma coisa?')

      described_class.perform_now(conversation, assistant)

      expect(Captain::ToolTraceWindow.open?).to be(false)
      expect(Captain::ToolTraceWindow.calls).to eq([])
    end
  end
end
