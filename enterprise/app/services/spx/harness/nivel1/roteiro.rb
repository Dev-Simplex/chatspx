# Nível 1 do harness: SEGURANÇA DETERMINÍSTICA.
#
# A diferença para o nível 2 (Spx::Conduta::Regressao) é o que está sob teste. Lá o sujeito é o
# modelo, o resultado é estatístico e a régua é um piso de acertos em N rodadas. Aqui o modelo
# é ROTEIRIZADO — a sequência de chamadas está escrita no cenário — e o sujeito são as
# ferramentas reais, as travas determinísticas e o que o cliente de fato recebe. Por isso a
# asserção é binária: aconteceu ou não aconteceu, sem piso e sem variância.
#
# As ferramentas são as de produção, instanciadas de verdade. O que é falso é só o mundo lá
# fora: o HTTP é mockado no limite da rede (WebMock), não nos métodos da própria tool. Mockar
# `fetch_detalhes` testaria o que sobra depois da parte que costuma quebrar — a classificação
# de falha, o corpo ilegível, o 2xx sem conteúdo, o timeout de uma AÇÃO.
#
# O que o roteiro devolve é observável, não interpretado: o texto que a ferramenta entregou ao
# modelo, a linha de trace que ficou no banco, as mensagens que saíram para o cliente e a nota
# que o turno seguinte receberia. Nenhum desses depende de ler intenção.
class Spx::Harness::Nivel1::Roteiro
  # Uma chamada do roteiro e tudo que ela produziu.
  Passo = Struct.new(:tool, :args, :resultado, :trace, :mensagens, keyword_init: true) do
    # `status: ok` NÃO prova que a ação aconteceu — a enviar_fotos_imovel grava 'ok' também
    # quando a trava barra o envio. Quem responde "o cliente recebeu?" é a mensagem.
    def entregou_midia?
      mensagens.any? { |m| m.attachments.any? || m.content_attributes['interactive_payload'].present? }
    end

    def status
      trace&.status
    end
  end

  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
  end

  # `passos` é uma lista de `{ tool: 'enviar_fotos_imovel', args: { codigo: '9849' } }`.
  # Custom tool (HttpTool) entra como `{ custom_tool: <registro>, args: {...} }`.
  def executar(passos)
    passos.map { |passo| rodar(passo) }
  end

  # A nota que o PRÓXIMO turno receberia. É o único caminho pelo qual o retorno de uma
  # ferramenta sobrevive ao turno em que foi chamada, então é onde se vê se a falha de consulta
  # chega ao modelo como falha — ou some e vira lacuna que ele preenche de memória.
  def nota_do_proximo_turno
    Captain::Conversation::ToolContextNote.new(conversation: @conversation).text
  end

  private

  def rodar(passo)
    tool = instanciar(passo)
    ultimo_trace = Captain::ToolCall.where(conversation_id: @conversation.id).maximum(:id).to_i
    ultima_msg = @conversation.messages.maximum(:id).to_i

    resultado = tool.perform(contexto, **passo.fetch(:args, {}).symbolize_keys)

    Passo.new(tool: nome_da_tool(passo), args: passo[:args], resultado: resultado.to_s,
              trace: trace_depois(ultimo_trace), mensagens: mensagens_depois(ultima_msg))
  end

  def instanciar(passo)
    return Captain::Tools::HttpTool.new(@assistant, passo.fetch(:custom_tool)) if passo[:custom_tool]

    "Captain::Tools::#{passo.fetch(:tool).to_s.camelize}Tool".constantize.new(@assistant)
  end

  def nome_da_tool(passo)
    passo[:tool] || passo[:custom_tool].slug
  end

  def trace_depois(ultimo_id)
    Captain::ToolCall.where(conversation_id: @conversation.id).where(id: (ultimo_id + 1)..).order(:id).last
  end

  def mensagens_depois(ultimo_id)
    @conversation.messages.where(id: (ultimo_id + 1)..).order(:id).to_a
  end

  def contexto
    @contexto ||= Struct.new(:state).new({ conversation: { id: @conversation.id },
                                           contact: { id: @conversation.contact_id } })
  end
end
