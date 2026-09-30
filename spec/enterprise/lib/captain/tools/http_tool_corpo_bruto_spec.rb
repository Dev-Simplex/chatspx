require 'rails_helper'

# Saída formatada vazia tem DUAS causas, e confundi-las custava caro: uma recusa que o CRM
# devolve com HTTP 200 (`{"sucesso": false}`) renderizava vazio no template e caía no ramo
# "2xx sem corpo" — que para AÇÃO é confirmação. A ferramenta dizia ao modelo que a operação
# foi realizada quando o sistema a tinha recusado.
#
# A decisão passa a ser pelo corpo BRUTO, antes do template:
#
#   corpo bruto vazio  -> o servidor não mandou nada  -> AÇÃO confirma, CONSULTA desconhece
#   corpo bruto cheio  -> mandou e não soubemos ler   -> os dois: INDETERMINADO
#
# Encontrado pelo harness offline em 21/09 (§18.1 da auditoria), com os três corpos abaixo.
RSpec.describe Captain::Tools::HttpTool do
  # `captain_tool_context` liga o trace: o `perform` devolve String (a gem so sabe lidar com
  # String, e o TraceRecorder desembrulha antes de entregar), entao o status SEMANTICO so e
  # observavel na linha gravada em captain_tool_calls — que e, alias, por onde ele chega a nota
  # do turno seguinte e ao eval.
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  def status_gravado
    Captain::ToolCall.where(conversation_id: conversation.id).order(:id).last.status
  end

  def ferramenta(metodo:, template:)
    custom = create(:captain_custom_tool, account: account, http_method: metodo,
                                          endpoint_url: 'https://example.com/visitas',
                                          response_template: template)
    described_class.new(assistant, custom)
  end

  def responder(status:, body:, metodo: :post)
    stub_request(metodo, 'https://example.com/visitas').to_return(status: status, body: body)
  end

  describe 'a tool que AGE' do
    subject(:tool) { ferramenta(metodo: 'POST', template: '{{ response.visita_id }}') }

    # Corpo 1 da tabela: o CRM recusou, com HTTP 200. Era este que virava confirmação.
    it 'não confirma quando o 200 carrega a recusa no corpo' do
      responder(status: 200, body: '{"sucesso":false,"erro":"horário ocupado"}')

      expect(tool.perform(tool_context).to_s).to eq(described_class::ACAO_ILEGIVEL)
    end

    # Corpo 2: nem JSON é. O `parse_response_body` devolve o corpo cru, o Liquid não acha o
    # campo e rende vazio — mesmo desfecho, mesma causa.
    it 'não confirma quando o corpo do 200 nem é JSON' do
      responder(status: 200, body: 'ERRO INTERNO DO SISTEMA')

      expect(tool.perform(tool_context).to_s).to eq(described_class::ACAO_ILEGIVEL)
    end

    # Corpo 3, CONTROLE POSITIVO: template acha o campo, confirmação legítima. A correção não
    # pode ser "nunca confirmar".
    it 'confirma normalmente quando o template consegue ler a resposta' do
      responder(status: 200, body: '{"visita_id":900}')

      expect(tool.perform(tool_context).to_s).to eq('900')
    end

    # O OUTRO controle positivo, e o que a correção não podia quebrar: 204 é a resposta normal
    # de um cancelamento. Tratá-lo como desconhecido fazia o modelo cancelar de novo.
    it 'confirma o 204 sem corpo, que é a resposta normal de um cancelamento' do
      responder(status: 204, body: '')

      expect(tool.perform(tool_context).to_s).to eq(Captain::Tools::HttpAcao::ACAO_CONFIRMADA)
    end

    it 'confirma o 200 com corpo em branco, que também é corpo bruto vazio' do
      responder(status: 200, body: "  \n ")

      expect(tool.perform(tool_context).to_s).to eq(Captain::Tools::HttpAcao::ACAO_CONFIRMADA)
    end

    it 'grava a ação ilegível como desconhecida, não como ok' do
      responder(status: 200, body: '{"sucesso":false}')
      tool.perform(tool_context)

      expect(status_gravado).to eq('desconhecido')
    end
  end

  describe 'a tool que CONSULTA' do
    subject(:tool) { ferramenta(metodo: 'GET', template: '{{ response.pedido_id }}') }

    # A mensagem precisa dizer o que de fato aconteceu. "Veio sem conteúdo" é falso aqui — o
    # sistema mandou conteúdo — e é dessa afirmação falsa que o modelo conclui ausência.
    it 'diz que o conteúdo não pôde ser extraído, e não que veio sem conteúdo' do
      responder(status: 200, body: '{"erro":"não autorizado"}', metodo: :get)

      resultado = tool.perform(tool_context)

      expect(resultado.to_s).to eq(described_class::CONTEUDO_ILEGIVEL)
      expect(resultado.to_s).not_to include('veio sem conteúdo')
      expect(status_gravado).to eq('desconhecido')
    end

    it 'continua dizendo "veio sem conteúdo" quando o corpo bruto está mesmo vazio' do
      responder(status: 204, body: '', metodo: :get)

      expect(tool.perform(tool_context).to_s).to eq(described_class::SEM_CONTEUDO)
    end

    # Em nenhum dos dois a ausência é confirmada: `vazio_completo` é o único estado que
    # autoriza dizer "não temos", e ele não pode sair daqui.
    it 'nunca carimba ausência confirmada' do
      responder(status: 200, body: '{"erro":"x"}', metodo: :get)
      tool.perform(tool_context)

      expect(status_gravado).not_to eq('vazio_completo')
    end
  end
end
