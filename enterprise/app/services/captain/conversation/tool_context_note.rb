# O que as ferramentas devolveram NESTE atendimento, de volta ao contexto do turno seguinte.
#
# O histórico do agente é remontado a cada turno a partir das `Message` do banco
# (ResponseBuilderJob#collect_previous_messages). Retorno de ferramenta não é mensagem, então
# ele vive só dentro da rodada em que a ferramenta foi chamada e SOME no turno seguinte — o
# agente fica com a própria fala, que é um resumo do resumo.
#
# O estrago é sempre o mesmo: ele afirma de memória o que a ferramenta já tinha respondido.
# Caso real (Tozi, conv 36940): a busca devolveu `[AVULSO — fora de condomínio fechado]` para
# duas casas; dois turnos depois o cliente perguntou se eram em condomínio fechado e a IA
# confirmou que sim, duas vezes. O dado existia e não estava mais à vista.
#
# Esta nota devolve só FATO — a chamada, os argumentos e o que voltou. O que fazer com isso é
# CONDUTA e mora no prompt do agente, no banco da conta. Mesma disciplina da
# EpisodeContinuityNote e da HumanHistoryNote: nota que dá ordem vira exemplo pro modelo copiar.
class Captain::Conversation::ToolContextNote
  # Quantas chamadas entram. O que importa é o passado RECENTE do atendimento; ir além disso
  # empurra o turno do cliente para longe no contexto sem devolver informação nova.
  LIMITE_CHAMADAS = 6
  # Corte por retorno. O trace já chega truncado em 1.500 (TraceRecorder::RESULT_PREVIEW_LIMIT);
  # aqui o corte é menor porque são várias chamadas somadas no mesmo preâmbulo.
  LIMITE_RESULTADO = 700
  CABECALHO = '[Contexto do sistema: o que as ferramentas já devolveram neste atendimento. ' \
              'É o dado que você mesma consultou — vale mais que a sua lembrança dele. ' \
              'Se precisar de algo que não está aqui, consulte de novo.'.freeze

  # `.present?` no fim porque `cast(nil)` devolve nil, e predicado que devolve nil obriga
  # todo chamador a lembrar disso.
  def self.enabled_for?(account)
    ActiveModel::Type::Boolean.new.cast(account&.custom_attributes&.dig('captain_tool_context')).present?
  end

  # `desde` é a fronteira do atendimento atual, quando a conta usa janela por episódio. Sem
  # ela a nota cobriria o fio perpétuo do contato e traria busca de meses atrás como se fosse
  # desta conversa.
  def initialize(conversation:, desde: nil)
    @conversation = conversation
    @desde = desde
  end

  # String pro histórico do turno, ou nil quando não há o que lembrar.
  def text
    return unless self.class.enabled_for?(@conversation.account)

    chamadas = buscar
    return if chamadas.empty?

    montar(chamadas)
  rescue StandardError => e
    # Best-effort: contexto a mais nunca pode derrubar o atendimento.
    Rails.logger.warn("[ToolContextNote] conv=#{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def buscar
    escopo = Captain::ToolCall.for_conversation(@conversation.id).where(status: 'ok')
    escopo = escopo.where('captain_tool_calls.created_at >= ?', @desde) if @desde.present?
    # Pega as ÚLTIMAS e devolve em ordem cronológica: o preâmbulo se lê como a linha do tempo
    # do atendimento, não de trás pra frente.
    escopo.order(created_at: :desc).limit(LIMITE_CHAMADAS).to_a.reverse
  end

  def montar(chamadas)
    linhas = [CABECALHO]
    chamadas.each { |c| linhas << linha(c) }
    "#{linhas.join("\n")}]"
  end

  def linha(chamada)
    "· #{chamada.tool_name}#{argumentos(chamada)} devolveu: #{resultado(chamada)}"
  end

  def argumentos(chamada)
    args = chamada.args
    return '' unless args.is_a?(Hash) && args.any?

    "(#{args.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')})"
  end

  def resultado(chamada)
    texto = chamada.result_preview.to_s.gsub(/\s+/, ' ').strip
    return '(sem retorno)' if texto.empty?
    return texto if texto.length <= LIMITE_RESULTADO

    "#{texto[0, LIMITE_RESULTADO]}…"
  end
end
