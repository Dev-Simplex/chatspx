require 'rails_helper'

# O trace é best-effort por construção: ele nunca quebra a tool, e quando o insert falha a
# exceção é engolida e só vai para o log. Isso é certo — trace não pode derrubar atendimento.
# O preço é que a falha é SILENCIOSA, e uma resposta em latin-1 bastava para a chamada sumir:
# o Postgres recusa a linha inteira quando o texto tem byte que não é UTF-8 válido.
#
# Sem linha em `captain_tool_calls`, a chamada fica fora da nota do turno seguinte e fora do
# eval. O modelo perde o retorno que ele mesmo consultou e volta a responder de memória — que é
# exatamente o defeito que a nota existe para fechar.
RSpec.describe Captain::Tools::TraceRecorder do
  # `captain_tool_context` é o que liga o trace (Captain::ToolCall.gravar_para?).
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }
  let(:custom_tool) do
    create(:captain_custom_tool, account: account, http_method: 'GET',
                                 endpoint_url: 'https://example.com/pedido', response_template: nil)
  end
  let(:tool) { Captain::Tools::HttpTool.new(assistant, custom_tool) }
  let(:traces) { Captain::ToolCall.where(conversation_id: conversation.id) }

  # "Pedido não localizado" em ISO-8859-1: o `ã` vira o byte 0xE3, que não é UTF-8 válido.
  # É a resposta de um CRM legado qualquer, não um caso de laboratório.
  let(:latin1) { 'Pedido nao localizado: sessao expirada'.sub('sessao', "sess\xE3o").b }

  before do
    stub_request(:get, 'https://example.com/pedido').to_return(status: 200, body: latin1)
  end

  it 'grava o trace mesmo quando o corpo não é UTF-8 válido' do
    tool.perform(tool_context)

    expect(traces.count).to eq(1)
  end

  # O resto do texto FICA. Descartar a linha toda por causa de um byte trocaria um defeito por
  # outro: trace ilegível é pior que trace com um `?` no meio.
  it 'preserva o texto ao redor do byte inválido' do
    tool.perform(tool_context)

    preview = traces.first.result_preview
    expect(preview).to include('Pedido nao localizado')
    expect(preview).to include('expirada')
    expect(preview.encoding).to eq(Encoding::UTF_8)
    expect(preview).to be_valid_encoding
  end

  it 'não altera resultado que já é UTF-8 válido' do
    stub_request(:get, 'https://example.com/pedido').to_return(status: 200, body: 'pedido 77 em rota')

    tool.perform(tool_context)

    expect(traces.first.result_preview).to eq('pedido 77 em rota')
  end

  # O corte por tamanho acontece DEPOIS da normalização: fatiar por caractere uma string de
  # codificação inválida é o que não tem resposta definida.
  it 'corta no limite mesmo com byte inválido no meio' do
    longo = ("\xE3ab" * 1000).b
    stub_request(:get, 'https://example.com/pedido').to_return(status: 200, body: longo)

    tool.perform(tool_context)

    expect(traces.first.result_preview.length).to eq(described_class::RESULT_PREVIEW_LIMIT)
  end
end
