require 'rails_helper'

# 6.02 — o RESPONDEDOR REAL, sem dublê de si mesmo.
#
# Os outros specs do bloco injetam `responder:` — uma lambda que devolve String. Isso
# testa a execução do conjunto, e é legítimo; mas deixava o respondedor de produção
# INTEIRO sem cobertura, e foi exatamente ali que o defeito morava: `output.to_s`
# julgava o inspect do Hash, com o `reasoning` do modelo dentro.
#
# Aqui a classe sob teste é a de verdade. O que está dublado é só a FRONTEIRA — o
# engine — e ele devolve a FORMA REAL: `Agents::RunResult` (Struct de output/messages/
# usage/error/context, ai-agents 0.12.0), com `output` no formato do
# `Captain::ResponseSchema`, que é o que TODO assistente do Captain usa.
#
# Nenhum exemplo chama IA: `run_raw` nunca é executado de verdade.
RSpec.describe Captain::Eval::AssistantResponder do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }

  # A saída de um agente com response_schema: a fala em `response`, o pensamento em
  # `reasoning`. É este Hash que `result.output` devolve.
  def resultado(response:, reasoning: 'pensamento do modelo', messages: [])
    Agents::RunResult.new(
      output: { 'response' => response, 'reasoning' => reasoning },
      messages: messages, usage: {}, error: nil, context: { current_agent: 'Atendente' }
    )
  end

  # A forma real das mensagens do run (Agents::Helpers::MessageExtractor): chaves
  # símbolo, `role` símbolo.
  def fala_do_assistente(conteudo)
    { role: :assistant, content: conteudo, agent_name: 'Atendente' }
  end

  def responde_com(run_result, &tool_trace)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    allow(runner).to receive(:run_raw) do
      tool_trace&.call
      run_result
    end
  end

  after { Captain::ToolTraceWindow.close! }

  describe 'o texto que vai para o juiz' do
    it 'is the SPOKEN answer — not the Hash with the reasoning inside' do
      responde_com(
        resultado(response: 'Abrimos das 9h às 18h.',
                  reasoning: 'o visitante insistiu em desconto; evitei prometer desconto')
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['que horas abre?'])

      expect(saida[:resposta]).to eq('Abrimos das 9h às 18h.')
      expect(saida[:resposta]).not_to include('desconto')
      expect(saida[:resposta]).not_to include('reasoning')
    end

    # O sintoma exato do 6.02: `{"response"=>"...", "reasoning"=>"..."}` inteiro como
    # texto julgado. Se voltar, esta asserção cai.
    it 'never carries the serialized structure into the judged text' do
      responde_com(resultado(response: 'Claro, posso ajudar.'))

      saida = described_class.new.call(assistant: assistant, mensagens: ['oi'])

      expect(saida[:resposta]).not_to match(/["']response["']\s*=>/)
    end

    it 'keeps a plain string output as it is — agente sem schema não quebra' do
      responde_com(
        Agents::RunResult.new(output: 'Resposta em texto puro', messages: [], usage: {}, error: nil, context: nil)
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['oi'])

      expect(saida[:resposta]).to eq('Resposta em texto puro')
    end
  end

  describe 'o turno que termina em transferência' do
    # `response` vem VAZIO no handoff — a fala de ponte ficou na última mensagem do
    # assistente. Sem o fallback, o juiz recebia string vazia e todo `contem` reprovava.
    it 'reads the bridge line from the last assistant message, hash-rocket and all' do
      responde_com(
        resultado(response: '', reasoning: 'transferindo',
                  messages: [fala_do_assistente('{"response"=>"Vou te passar pra Bruna, um instante.", "reasoning"=>"handoff"}')])
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['quero falar com humano'])

      expect(saida[:resposta]).to eq('Vou te passar pra Bruna, um instante.')
    end

    it 'reads it when the model serialized valid JSON instead' do
      responde_com(
        resultado(response: '', reasoning: 'transferindo',
                  messages: [fala_do_assistente('{"response": "Já chamo a Bruna.", "reasoning": "handoff"}')])
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['quero falar com humano'])

      expect(saida[:resposta]).to eq('Já chamo a Bruna.')
    end

    it 'reads plain text when the last assistant message is plain text' do
      responde_com(
        resultado(response: '', messages: [fala_do_assistente('Um instante que eu te transfiro.')])
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['humano'])

      expect(saida[:resposta]).to eq('Um instante que eu te transfiro.')
    end

    it 'gives an empty answer — not the word nil — when there is nothing said at all' do
      responde_com(
        Agents::RunResult.new(output: nil, messages: [], usage: {}, error: nil, context: nil)
      )

      saida = described_class.new.call(assistant: assistant, mensagens: ['oi'])

      expect(saida[:resposta]).to eq('')
    end
  end

  describe 'o regime de execução' do
    it 'runs the engine OUTSIDE any conversation — é o que sustenta o dry_run do bloco' do
      responde_com(resultado(response: 'oi'))

      described_class.new.call(assistant: assistant, mensagens: ['oi'])

      expect(Captain::Assistant::AgentRunnerService)
        .to have_received(:new).with(assistant: assistant, conversation: nil)
    end

    it 'sends every turn as a user message, in order' do
      responde_com(resultado(response: 'oi'))

      described_class.new.call(assistant: assistant, mensagens: %w[primeira segunda])

      expect(runner).to have_received(:run_raw).with(
        message_history: [{ content: 'primeira', role: 'user' }, { content: 'segunda', role: 'user' }]
      )
    end
  end

  describe 'a janela de tool calls (a mesma do 6.01)' do
    it 'reports the tools the run actually called' do
      responde_com(resultado(response: 'achei três imóveis')) do
        Captain::ToolTraceWindow.record(tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa A')
        Captain::ToolTraceWindow.record(tool_name: 'buscar_imovel', status: 'ok', result_preview: 'Casa B')
      end

      saida = described_class.new.call(assistant: assistant, mensagens: ['tem casa?'])

      expect(saida[:ferramentas]).to eq(['buscar_imovel'])
      expect(saida[:tool_calls].size).to eq(2)
      expect(saida[:handoff]).to be(false)
    end

    it 'flags the handoff by the tool that was called' do
      responde_com(resultado(response: '')) do
        Captain::ToolTraceWindow.record(tool_name: 'transferir_para_humano', status: 'ok', result_preview: 'ok')
      end

      saida = described_class.new.call(assistant: assistant, mensagens: ['humano'])

      expect(saida[:handoff]).to be(true)
    end

    it 'closes the window even when the engine blows up — senão a próxima resposta herda as chamadas desta' do
      allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
      allow(runner).to receive(:run_raw).and_raise(StandardError, 'timeout do provedor')

      expect { described_class.new.call(assistant: assistant, mensagens: ['oi']) }
        .to raise_error(StandardError, 'timeout do provedor')
      expect(Captain::ToolTraceWindow).not_to be_open
    end
  end

  # O PROBE do bloco, ponta a ponta com o respondedor real: a palavra proibida existe
  # SÓ no raciocínio. Com `output.to_s`, este caso reprovava.
  describe 'o veredito de um caso com o respondedor real' do
    it 'does not fail a case for a word that only exists in the reasoning' do
      caso = create(:captain_eval_case, captain_assistant: assistant, account: account,
                                        titulo: 'não promete desconto',
                                        expectativas: { 'nao_contem' => ['desconto'] })
      responde_com(
        resultado(response: 'Nossos preços de tabela estão no site.',
                  reasoning: 'o visitante pediu desconto duas vezes; não ofereci desconto')
      )

      veredito = Captain::Eval::CaseRunnerService.new(
        assistant: assistant, eval_case: caso, responder: described_class.new
      ).perform

      expect(veredito[:passou]).to be(true)
      expect(veredito[:resposta]).to eq('Nossos preços de tabela estão no site.')
    end

    it 'still fails the case when the ANSWER itself says the forbidden word' do
      caso = create(:captain_eval_case, captain_assistant: assistant, account: account,
                                        titulo: 'não promete desconto',
                                        expectativas: { 'nao_contem' => ['desconto'] })
      responde_com(resultado(response: 'Posso te dar desconto de 10%.', reasoning: 'nada aqui'))

      veredito = Captain::Eval::CaseRunnerService.new(
        assistant: assistant, eval_case: caso, responder: described_class.new
      ).perform

      expect(veredito[:passou]).to be(false)
      expect(veredito[:findings].first['categoria']).to eq('contem_o_proibido')
    end

    it 'judges the handoff bridge line, not the empty string it used to judge' do
      caso = create(:captain_eval_case, captain_assistant: assistant, account: account,
                                        titulo: 'anuncia a transferência',
                                        expectativas: { 'contem' => ['Bruna'] })
      responde_com(
        resultado(response: '', reasoning: 'transferindo',
                  messages: [fala_do_assistente('{"response"=>"Vou te passar pra Bruna.", "reasoning"=>"handoff"}')])
      )

      veredito = Captain::Eval::CaseRunnerService.new(
        assistant: assistant, eval_case: caso, responder: described_class.new
      ).perform

      expect(veredito[:passou]).to be(true)
    end
  end
end
