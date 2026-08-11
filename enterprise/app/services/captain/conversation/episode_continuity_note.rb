# Contexto de REENTRADA por episódio: este contato já foi atendido nesta conversa antes,
# e o atendimento de agora é OUTRO.
#
# Com `lock_to_single_conversation` o fio do contato é perpétuo, então sem isto um desabafo
# de fevereiro chega ao modelo como o turno imediatamente anterior à mensagem de hoje (caso
# real: conv 20215, 171 dias viraram nada — a IA registrou urgência de um portão que já
# tinha sido resolvido e disparou handoff com dossiê falso).
#
# Devolve só FATO — quantos atendimentos houve, quando, quem conduziu, como encerraram. O
# que fazer com isso (não retomar o assunto velho, tratar como assunto novo) é CONDUTA e
# mora no prompt do agente, no banco da conta: nota de contexto que dá ordem vira exemplo
# pro modelo copiar. Mesma disciplina da Captain::Conversation::HumanHistoryNote.
class Captain::Conversation::EpisodeContinuityNote
  # Contato com 15 atendimentos não vira 15 linhas.
  DETALHADOS = 3
  IA_SENDERS = %w[Captain::Assistant AgentBot].freeze
  FECHAMENTO = {
    'resolve' => 'encerrado pelo time',
    'gap' => 'encerrado por inatividade',
    'hsm_campanha' => 'encerrado por campanha nova'
  }.freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  # String pro histórico do turno, ou nil quando não há atendimento anterior.
  def text
    # Fronteira derivada no instante do turno quando a tabela do cron ainda não a tem —
    # sem isso a nota também só apareceria a partir do segundo turno da reentrada.
    fronteira = Captain::Conversation::EpisodeBoundary.new(conversation: @conversation)
    atual = fronteira.atual
    # Contato novo (atendimento 1) não tem do que ser lembrado — a nota nasce na reentrada.
    return if atual.nil? || atual.seq.to_i <= 1

    anteriores = fronteira.anteriores(limite: DETALHADOS)
    return if anteriores.empty?

    montar(atual, anteriores)
  rescue StandardError => e
    Rails.logger.warn("[EpisodeContinuityNote] conv=#{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def montar(atual, anteriores)
    total = atual.seq.to_i - 1
    linhas = ['[Contexto do sistema: este contato já foi atendido nesta conversa antes de hoje.']
    linhas << "#{total} #{total == 1 ? 'atendimento anterior' : 'atendimentos anteriores'}."
    # Os ocultos são os MAIS ANTIGOS: vêm antes da lista, que é renderizada do mais antigo
    # pro mais recente.
    ocultos = total - anteriores.size
    linhas << "E outros #{ocultos} antes destes." if ocultos.positive?
    anteriores.reverse_each { |episodio| linhas << linha_do_episodio(episodio) }
    linhas << recencia(anteriores.first)
    linhas << concluidos
    linhas << abertura(atual)
    "#{linhas.compact.join("\n")}]"
  end

  def linha_do_episodio(episodio)
    partes = ["— #{data(episodio.started_at)}"]
    conduzido = conduzido_por(episodio)
    partes << "conduzido por #{conduzido}" if conduzido
    partes << (FECHAMENTO[episodio.boundary_reason] || 'encerrado')
    linha = "#{partes.join(', ')}."
    resumo = resumos[episodio.first_message_id]
    resumo.present? ? "#{linha} #{resumo.strip}" : linha
  end

  # Quem falou pelo lado do atendimento naquele episódio. Derivado das mensagens (sempre
  # existe), não do veredito do juiz — que só cobre 32% dos episódios fechados.
  def conduzido_por(episodio)
    # `reorder(nil)` obrigatório: Message tem default_scope ordenando por created_at, e o
    # Postgres recusa SELECT DISTINCT com ORDER BY numa coluna fora da lista selecionada
    # (PG::InvalidColumnReference). Mesma armadilha de default_scope que o HumanHistoryNote
    # documenta pro caso do `.reorder(desc)`.
    tipos = @conversation.messages
                         .where(id: episodio.first_message_id..episodio.last_message_id)
                         .where(message_type: :outgoing, private: false)
                         .reorder(nil)
                         .distinct.pluck(:sender_type)
    ia = tipos.any? { |tipo| IA_SENDERS.include?(tipo) }
    humano = tipos.include?('User')
    return 'IA e humano' if ia && humano
    return 'IA' if ia

    'humano' if humano
  end

  # Bônus quando existe: resumo que o juiz do eval já escreveu daquele atendimento. A
  # chave é o first_message_id, não o id do episódio: a fronteira pode ter vindo da
  # DERIVAÇÃO, que não tem linha na tabela — e aí não haveria id pra casar.
  def resumos
    @resumos ||= mapear_resumos
  rescue StandardError
    {}
  end

  def mapear_resumos
    episodios = Captain::ConversationEpisode.where(conversation_id: @conversation.id).pluck(:id, :first_message_id).to_h
    return {} if episodios.empty?

    avaliados = Captain::ConversationEval.where(episode_id: episodios.keys).pluck(:episode_id, :resumo).to_h
    episodios.filter_map { |id, primeira| [primeira, avaliados[id]] if avaliados[id].present? }.to_h
  end

  def recencia(mais_recente)
    fim = mais_recente.ended_at
    return if fim.blank?

    dias = ((Time.current - fim) / 1.day).floor
    return 'O último terminou hoje.' if dias <= 0

    "O último terminou há #{dias} #{dias == 1 ? 'dia' : 'dias'}."
  end

  # Declaração explícita de "isso acabou", feita por gente. Só os concluídos: os pendentes
  # já vão no contexto da conversa (snippets/conversation.liquid).
  def concluidos
    itens = @conversation.custom_attributes&.dig('assuntos_checklist')
    return unless itens.is_a?(Array)

    feitos = itens.select { |item| item.is_a?(Hash) && item['done'] }.filter_map { |item| item['text'].to_s.strip.presence }
    return if feitos.empty?

    "Assuntos já concluídos: #{feitos.join('; ')}."
  end

  def abertura(atual)
    inicio = atual.started_at
    return 'A mensagem a seguir abre um atendimento novo.' if inicio.blank?

    "A mensagem a seguir abre um atendimento novo, em #{data(inicio)} às #{hora(inicio)}."
  end

  def data(instante)
    instante.in_time_zone(fuso).strftime('%d/%m/%Y')
  end

  def hora(instante)
    instante.in_time_zone(fuso).strftime('%H:%M')
  end

  # `Time.zone` (TZ do deployment — America/Manaus na Tozi), NÃO `inbox.timezone`: essa
  # coluna está no default 'UTC' na inbox 91 e renderizaria a hora 4h adiantada, dizendo
  # ao modelo que o atendimento abriu 13:40 quando abriu 09:40. Cada cliente do SPX roda
  # na própria VM, então o fuso do app é o do cliente.
  # ⚠️ `Account` NÃO responde a `timezone` — chamar isso levanta NoMethodError.
  def fuso
    Time.zone
  end
end
