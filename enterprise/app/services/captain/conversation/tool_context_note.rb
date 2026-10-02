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
# A nota também carrega a consulta que FALHOU. Antes ela filtrava `status: 'ok'` e a chamada
# falha simplesmente não entrava: o modelo via a lacuna como "nunca consultei" em vez de
# "consultei e a consulta falhou", e completava de memória — o mesmo defeito por outro caminho.
#
# Esta nota devolve só FATO — a chamada, os argumentos e o que voltou (ou que não voltou). O que
# fazer com isso é CONDUTA e mora no prompt do agente, no banco da conta. Mesma disciplina da
# EpisodeContinuityNote e da HumanHistoryNote: nota que dá ordem vira exemplo pro modelo copiar.
class Captain::Conversation::ToolContextNote
  # Quantas chamadas BEM-SUCEDIDAS entram. O que importa é o passado RECENTE do atendimento; ir
  # além disso empurra o turno do cliente para longe no contexto sem devolver informação nova.
  LIMITE_CHAMADAS = 6
  # Falhas têm orçamento SEPARADO, e não competem com o dos fatos: uma rajada de timeouts não
  # pode empurrar pra fora da nota o preço que a busca anterior trouxe. Três bastam para o modelo
  # saber que a consulta não respondeu; a quarta não acrescenta.
  LIMITE_FALHAS = 3
  # Orçamento TOTAL dos retornos na nota, repartido da chamada mais recente para a mais antiga.
  # É o mesmo teto de antes (6 chamadas × 700), só que somado: o corte fixo de 700 por chamada
  # guardava o prefácio de regras da busca e cortava a lista de imóveis que vem depois dele
  # (conv 28718: sem os códigos na nota, a IA inventou código para enviar as fotos), enquanto a
  # chamada de registro ao lado quase não ocupava a sua cota. Cada retorno já chega truncado em
  # 1.500 pelo trace (TraceRecorder::RESULT_PREVIEW_LIMIT), e esse é o teto natural por chamada.
  ORCAMENTO_RESULTADOS = LIMITE_CHAMADAS * 700
  # A linha de falha diz que falhou e por quê, e isso cabe em pouco. Teto baixo de propósito:
  # é o que garante que ela custe ~1 linha e não desloque fato bom.
  LIMITE_MOTIVO = 200

  CABECALHO = '[Contexto do sistema: o que as ferramentas já devolveram neste atendimento. ' \
              'É o dado que você mesma consultou — vale mais que a sua lembrança dele. ' \
              'Se precisar de algo que não está aqui, consulte de novo.'.freeze
  # Só entra quando há linha de falha na nota. Sem falha, a nota sai byte a byte igual à de
  # antes deste PR — é o que mantém a mudança mensurável no harness de conduta.
  AVISO_FALHA = ' Linha marcada NÃO CONFIRMOU é consulta que não retornou dado: ' \
                'isso não é ausência do dado.'.freeze

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

  def escopo_base
    escopo = Captain::ToolCall.for_conversation(@conversation.id)
    escopo = escopo.where('captain_tool_calls.created_at >= ?', @desde) if @desde.present?
    escopo
  end

  def buscar
    confirmadas = escopo_base.where(status: Captain::Tools::Result::CONFIRMADOS)
                             .order(created_at: :desc).limit(LIMITE_CHAMADAS).to_a
    # Ordem cronológica no fim: o preâmbulo se lê como a linha do tempo do atendimento, não de
    # trás pra frente. Fato e falha entram na MESMA linha do tempo — é a sequência que mostra
    # que a busca falhou DEPOIS do preço que veio antes.
    (confirmadas + falhas_relevantes(confirmadas)).sort_by(&:created_at)
  end

  # Falha que uma consulta POSTERIOR da mesma ferramenta resolveu não é mais notícia — mostrar as
  # duas faria o modelo dizer que a consulta falhou tendo o dado na mão. E ferramenta que falhou
  # cinco vezes seguidas vira UMA linha: repetição não informa e ocupa a nota.
  def falhas_relevantes(confirmadas)
    ultimo_sucesso = confirmadas.group_by(&:tool_name)
                                .transform_values { |chamadas| chamadas.max_by(&:created_at).created_at }

    escopo_base.where(status: Captain::Tools::Result::NAO_CONFIRMADOS)
               .order(created_at: :desc).limit(LIMITE_FALHAS * 5).to_a
               .reject { |c| superada?(c, ultimo_sucesso[c.tool_name]) }
               .uniq(&:tool_name)
               .first(LIMITE_FALHAS)
  end

  def superada?(chamada, sucesso_em)
    sucesso_em.present? && sucesso_em > chamada.created_at
  end

  def montar(chamadas)
    houve_falha = chamadas.any? { |c| nao_confirmou?(c) }
    linhas = [houve_falha ? "#{CABECALHO}#{AVISO_FALHA}" : CABECALHO]
    cotas = cotas_de_resultado(chamadas)
    chamadas.each { |c| linhas << linha(c, cotas[c.id]) }
    "#{linhas.join("\n")}]"
  end

  def nao_confirmou?(chamada)
    Captain::Tools::Result::NAO_CONFIRMADOS.include?(chamada.status.to_s)
  end

  # A mais recente leva o que precisar; as anteriores levam o que sobrar. A recente é a que o
  # turno seguinte mais usa, e as antigas costumam ser registro curto que cabe inteiro na sobra.
  def cotas_de_resultado(chamadas)
    restante = ORCAMENTO_RESULTADOS
    chamadas.reject { |c| nao_confirmou?(c) }.reverse.to_h do |c|
      cota = [texto_resultado(c).length, restante].min
      restante -= cota
      [c.id, cota]
    end
  end

  def linha(chamada, cota)
    return "· #{chamada.tool_name}#{argumentos(chamada)} NÃO CONFIRMOU: #{motivo(chamada)}" if nao_confirmou?(chamada)

    "· #{chamada.tool_name}#{argumentos(chamada)} devolveu: #{resultado(chamada, cota)}"
  end

  def argumentos(chamada)
    args = chamada.args
    return '' unless args.is_a?(Hash) && args.any?

    "(#{args.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')})"
  end

  def texto_resultado(chamada)
    chamada.result_preview.to_s.gsub(/\s+/, ' ').strip
  end

  def resultado(chamada, cota)
    texto = texto_resultado(chamada)
    return '(sem retorno)' if texto.empty?
    return texto if texto.length <= cota

    "#{texto[0, cota]}…"
  end

  # Exceção não deixa `result_preview` (o recorder grava nil), então o motivo vem da coluna
  # `error`. Quem devolveu Result tipado tem o próprio texto no preview e ele é melhor: foi
  # escrito para o modelo ler.
  def motivo(chamada)
    texto = chamada.result_preview.presence || chamada.error.presence
    texto = texto.to_s.gsub(/\s+/, ' ').strip
    return 'a consulta não retornou dado' if texto.empty?
    return texto if texto.length <= LIMITE_MOTIVO

    "#{texto[0, LIMITE_MOTIVO]}…"
  end
end
