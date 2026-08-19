require 'rails_helper'

# 6.02 — a execução do conjunto.
#
# NENHUM EXEMPLO CHAMA IA. O respondedor é injetado: uma lambda que devolve o texto que
# o exemplo quiser. É o mesmo ponto de injeção que a tela usa em produção com o
# respondedor real, e é por isso que ele existe.
RSpec.describe Captain::Eval::RunService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  # Dublê: devolve sempre a mesma saída, seja qual for o caso.
  def responder_fixo(resposta:, ferramentas: [], handoff: false, tool_calls: [])
    ->(**) { { resposta: resposta, ferramentas: ferramentas, handoff: handoff, tool_calls: tool_calls } }
  end

  describe 'o modo de execução' do
    it 'refuses to run outside dry_run — o outro modo não existe' do
      expect { described_class.new(assistant: assistant, dry_run: false) }
        .to raise_error(ArgumentError, /dry_run/)
    end

    it 'stamps every run as dry_run, so the history says under which regime the number was taken' do
      create(:captain_eval_case, captain_assistant: assistant, account: account)

      run = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform

      expect(run.dry_run).to be(true)
    end

    it 'never touches a conversation, a message or the response usage' do
      create(:captain_eval_case, captain_assistant: assistant, account: account)

      expect do
        described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform
      end.to not_change(Conversation, :count).and not_change(Message, :count)

      expect(account.reload.usage_limits[:captain][:responses][:consumed]).to eq(0)
    end

    it 'never calls an LLM service' do
      create(:captain_eval_case, captain_assistant: assistant, account: account)
      expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)
      expect(Captain::Llm::AssistantChatService).not_to receive(:new)

      described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform
    end
  end

  describe 'o veredito por caso' do
    let!(:caso_ok) do
      create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'diz o horário',
                                 expectativas: { 'contem' => ['das 9h'] })
    end
    let!(:caso_falha) do
      create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'não promete desconto',
                                 expectativas: { 'nao_contem' => ['desconto'] })
    end

    it 'counts what passed and what failed' do
      run = described_class.new(assistant: assistant,
                                responder: responder_fixo(resposta: 'Abrimos das 9h e posso te dar desconto')).perform

      expect(run.casos_total).to eq(2)
      expect(run.casos_ok).to eq(1)
      expect(run.casos_falha).to eq(1)
      expect(run.aprovacao).to eq(50.0)
      expect(run.status).to eq('concluida')
    end

    it 'keeps the answer and the reason of each case' do
      run = described_class.new(assistant: assistant,
                                responder: responder_fixo(resposta: 'Abrimos das 9h e posso te dar desconto')).perform

      reprovado = run.results.find_by(eval_case_id: caso_falha.id)
      expect(reprovado.passou).to be(false)
      expect(reprovado.resposta).to include('desconto')
      expect(reprovado.findings.first['categoria']).to eq('contem_o_proibido')
      expect(run.results.find_by(eval_case_id: caso_ok.id).passou).to be(true)
    end

    # É o que amarra 6.02 a 6.01: a régua do veredito inclui a régua do envio.
    it 'fails a case whose answer would be RETAINED in production' do
      caso = create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'não nega o que achou')
      run = described_class.new(
        assistant: assistant,
        responder: responder_fixo(resposta: 'Não encontrei imóveis com esse perfil.',
                                  tool_calls: [{ tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A' }])
      ).perform

      resultado = run.results.find_by(eval_case_id: caso.id)
      expect(resultado.passou).to be(false)
      expect(resultado.findings.map { |f| f['categoria'] }).to include('contradisse_tool')
    end

    it 'fails the case instead of killing the set when the responder blows up' do
      create(:captain_eval_case, captain_assistant: assistant, account: account)
      explode = ->(**) { raise StandardError, 'timeout do provedor' }

      run = described_class.new(assistant: assistant, responder: explode).perform

      expect(run.status).to eq('concluida')
      expect(run.casos_falha).to eq(3)
      expect(run.results.first.findings.first['porque']).to include('timeout do provedor')
    end
  end

  describe 'a identidade do prompt' do
    before { create(:captain_eval_case, captain_assistant: assistant, account: account) }

    it 'is stamped on the run, with a readable snapshot' do
      run = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform

      expect(run.prompt_fingerprint).to be_present
      expect(run.prompt_snapshot['description']).to eq(assistant.description)
    end

    it 'changes when the prompt changes, and only then' do
      primeira = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform
      igual = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform
      assistant.update!(description: 'outra instrução para o agente')
      depois = described_class.new(assistant: assistant.reload, responder: responder_fixo(resposta: 'oi')).perform

      expect(igual.prompt_fingerprint).to eq(primeira.prompt_fingerprint)
      expect(depois.prompt_fingerprint).not_to eq(primeira.prompt_fingerprint)
    end
  end

  describe 'o custo' do
    it 'is stored with the run exactly as it was shown before running' do
      create(:captain_eval_case, captain_assistant: assistant, account: account)

      run = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform

      expect(run.custo_estimado['casos']).to eq(1)
      expect(run.custo_estimado['respostas']).to eq(1)
      expect(run.custo_estimado['tokens_estimados']).to be > 0
    end
  end

  describe 'os casos desativados' do
    it 'stay out of the run' do
      create(:captain_eval_case, captain_assistant: assistant, account: account, ativo: false)
      create(:captain_eval_case, captain_assistant: assistant, account: account, ativo: true)

      run = described_class.new(assistant: assistant, responder: responder_fixo(resposta: 'oi')).perform

      expect(run.casos_total).to eq(1)
    end
  end
end
