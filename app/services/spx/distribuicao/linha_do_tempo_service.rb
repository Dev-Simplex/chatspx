# Linha do tempo dos leads que entraram na fila PELO RODÍZIO (SPEC-RODIZIO §9).
#
# A tela de contabilização diz QUANTOS cada um recebeu. Isto conta o percurso de cada lead, como
# um rastreio de entrega: chegou → a IA cobriu → o motor designou → (expirou e foi repassado) →
# alguém pegou → resolveu. Read-only: lê o livro-razão, não decide nada.
#
# Um lead = uma designação `motivo: rodizio` MAIS os repasses que vieram dela. O repasse é uma
# linha nova no livro-razão (`repasse_sla`/`escalado_gestor`), e tratar cada linha como um lead
# escondia o fim da história: o lead que expirou com a Misya e hoje espera o Gelson aparecia
# "encerrado", e o Gelson nem o via na lista dele.
#
# Só leads que entraram pelo rodízio, de propósito: continuidade e pedido do cliente não passaram
# pela fila — medir a espera deles como se fosse rodízio inventaria um problema que não existe.
class Spx::Distribuicao::LinhaDoTempoService # rubocop:disable Metrics/ClassLength
  # Teto da lista por consultor. O total sem teto vai junto, para a tela dizer "mostrando 20 de 34".
  LIMITE = 20
  # Designação que fechou porque alguém ENCOSTOU no lead: é o fim da espera.
  ASSUMIDOS = %w[assumido engajado].freeze
  # Fechou sem ninguém encostar: o lead foi embora para outro corretor (ou para ninguém).
  PERDIDOS = %w[expirado substituido].freeze
  # As linhas que continuam o MESMO lead depois de uma designação perdida.
  REPASSES = %w[repasse_sla escalado_gestor].freeze
  SITUACOES = %w[espera atendimento resolvido perdido].freeze

  # `escopo` chega pronto do controller (conta + período + time), para o recorte ser exatamente o
  # mesmo da tabela em volta. `user_id` filtra os leads por onde o consultor PASSOU (recebeu pelo
  # rodízio ou por repasse); `situacao` é um dos SITUACOES ou 'repassado'.
  def initialize(escopo:, canais: {}, user_id: nil, limite: LIMITE, situacao: nil)
    @escopo = escopo
    @user_id = user_id.presence&.to_i
    @canais = canais
    @limite = limite
    @situacao = situacao.presence
  end

  def call
    do_consultor = @user_id ? todos.select { |lead| lead[:pessoas].include?(@user_id) } : todos
    filtrados = filtrar(do_consultor)
    {
      leads: filtrados.first(@limite),
      total: filtrados.size,
      contagem: contagem(do_consultor),
      consultores: consultores,
      media_espera_segundos: media_espera(do_consultor),
      # Os números do topo da tela: o período inteiro, sem o filtro de consultor.
      geral: { contagem: contagem(todos), media_espera_segundos: media_espera(todos) }
    }
  end

  private

  # Todos os leads do período, do que chegou por último para o primeiro. A ordem é a da pergunta
  # "o que entrou hoje e onde está?"; quem quer ver só os parados usa o filtro "Esperando".
  def todos
    @todos ||= raizes.map { |log| serializar(log) }.sort_by { |lead| [-lead[:chegou_em].to_i, -lead[:id]] }
  end

  def filtrar(leads)
    return leads if @situacao.blank?
    return leads.select { |lead| lead[:repassado] } if @situacao == 'repassado'

    leads.select { |lead| lead[:situacao] == @situacao }
  end

  # As contagens dos filtros: as quatro situações somam o total; "repassado" é um recorte por
  # cima delas (um lead repassado hoje pode estar esperando, em atendimento ou resolvido).
  def contagem(leads)
    base = SITUACOES.index_with { |situacao| leads.count { |lead| lead[:situacao] == situacao } }
    base.merge(todos: leads.size, repassado: leads.count { |lead| lead[:repassado] })
  end

  # Quem aparece em algum lead do período, para o filtro por consultor.
  def consultores
    por_pessoa = todos.flat_map { |lead| lead[:pessoas] }.tally
    por_pessoa.filter_map { |id, total| nomes[id] && { id: id, nome: nomes[id], total: total } }.sort_by { |item| item[:nome] }
  end

  # Média só de quem alguém pegou: lead ainda esperando não tem espera final, e contá-lo como se
  # tivesse acabado agora empurraria a média para cima a cada recarga da tela.
  def media_espera(leads)
    esperas = leads.select { |lead| lead[:pegou_em] }.pluck(:espera_segundos)
    esperas.any? ? (esperas.sum / esperas.size.to_f).round : nil
  end

  def raizes
    @raizes ||= @escopo.where(motivo: 'rodizio').includes(conversation: [:inbox, :contact]).to_a
  end

  def conversation_ids
    @conversation_ids ||= raizes.map(&:conversation_id).uniq
  end

  # Todas as designações das mesmas conversas, sem o recorte de período: o repasse de um lead
  # do dia 30 pode ter acontecido no dia 1º. Uma query só; o resto é em memória.
  def designacoes_por_conversa
    @designacoes_por_conversa ||= Spx::Distribuicao::Log.where(conversation_id: conversation_ids)
                                                        .order(:id)
                                                        .group_by(&:conversation_id)
  end

  def nomes
    @nomes ||= User.where(id: designacoes_por_conversa.values.flatten.filter_map(&:chosen_user_id) + usuarios_das_resolucoes)
                   .pluck(:id, :name).to_h
  end

  # A designação de rodízio e os repasses que a seguiram, enquanto cada uma terminou perdida.
  def cadeia(log)
    seguintes = designacoes_por_conversa.fetch(log.conversation_id, []).select { |outra| outra.id > log.id }
    seguintes.each_with_object([log]) do |outra, elos|
      break elos unless PERDIDOS.include?(elos.last.status) && REPASSES.include?(outra.motivo)

      elos << outra
    end
  end

  # A próxima designação da conversa que NÃO é deste lead: o contato voltou e começou outro ciclo.
  # Tudo o que acontece depois dela é de outro lead.
  def proximo_ciclo(cadeia)
    designacoes_por_conversa.fetch(cadeia.first.conversation_id, []).find { |outra| outra.id > cadeia.last.id }
  end

  # O contato que volta cai na MESMA conversa, com um evento por ciclo: vale o primeiro DENTRO
  # deste ciclo. O último da vida da conversa pode ser de um ciclo anterior (e o lead que ainda
  # espera apareceria resolvido) ou do seguinte (e o atendimento incharia).
  def eventos_de(nome)
    @eventos_de ||= {}
    @eventos_de[nome] ||= ReportingEvent.where(name: nome, conversation_id: conversation_ids)
                                        .where.not(event_end_time: nil)
                                        .order(:event_end_time)
                                        .pluck(:conversation_id, :event_end_time, :user_id)
                                        .group_by(&:first)
  end

  def usuarios_das_resolucoes
    eventos_de('conversation_resolved').values.flatten(1).filter_map(&:last)
  end

  def resolucao(conversation_id, inicio, fim)
    eventos_de('conversation_resolved').fetch(conversation_id, []).find do |_, instante, _|
      instante >= inicio && (fim.nil? || instante < fim)
    end
  end

  # A chegada DESTE lead: a última reabertura antes de o motor designar, ou o nascimento da
  # conversa quando ela nunca reabriu. NÃO é `conversations.created_at`: no WhatsApp o contato que
  # volta cai na mesma conversa, e a fase da IA trazia o tempo desde a primeira mensagem da vida
  # dele (medido: 24 dias), esmagando a espera, que é o que esta tela existe para mostrar.
  def chegada(log, designado)
    reaberturas = eventos_de('conversation_opened').fetch(log.conversation_id, []).map { |_, instante, _| instante }
    reaberturas.reverse.find { |instante| instante <= designado } || log.conversation&.created_at || designado
  end

  def segundos(inicio, fim)
    return 0 if inicio.blank? || fim.blank?

    [(fim - inicio).round, 0].max
  end

  # Tudo o que se sabe de UM ciclo do lead, calculado uma vez e lido pelo resto.
  def ciclo(log)
    elos = cadeia(log)
    designado = log.designado_em || log.created_at
    fim = proximo_ciclo(elos)&.then { |outra| outra.designado_em || outra.created_at }
    resolvido = resolucao(log.conversation_id, designado, fim)
    { log: log, elos: elos, designado: designado, fim: fim, chegou: chegada(log, designado),
      pegou: elos.find { |elo| ASSUMIDOS.include?(elo.status) },
      resolvido_em: resolvido&.second, resolvido_por: resolvido && nomes[resolvido.third] }
  end

  def serializar(log)
    c = ciclo(log)
    identificacao(log, c[:elos]).merge(
      chegou_em: c[:chegou],
      designado_em: c[:designado],
      pegou_em: c[:pegou]&.encerrado_em,
      resolvido_em: c[:resolvido_em],
      repassado: c[:elos].size > 1 || fim_perdido?(c[:elos]),
      espera_segundos: segundos(c[:designado], fim_da_espera(c)),
      eventos: eventos(c)
    ).merge(situacao(c))
  end

  def agora
    @agora ||= Time.zone.now
  end

  # A espera vai da primeira designação até alguém pegar — atravessando os repasses, porque para
  # o cliente é uma espera só. Sem ninguém pegar, corre até agora (ou até expirar/resolver).
  def fim_da_espera(ciclo)
    return ciclo[:pegou].encerrado_em if ciclo[:pegou]
    return ciclo[:elos].last.encerrado_em if fim_perdido?(ciclo[:elos])

    ciclo[:resolvido_em] || agora
  end

  def fim_perdido?(elos)
    PERDIDOS.include?(elos.last.status)
  end

  # Onde o lead está AGORA, e desde quando — é o selo do cartão ("Esperando Misya pegar há 1 d").
  # Sai daqui, e não da tela, para o selo e os filtros nunca discordarem. Resolvido vence tudo:
  # conversa encerrada não espera mais ninguém, mesmo que a designação tenha ficado aberta.
  def situacao(ciclo)
    ultimo = ciclo[:elos].last
    if ciclo[:resolvido_em]
      { situacao: 'resolvido', segundos_na_situacao: segundos(ciclo[:chegou], ciclo[:resolvido_em]) }
    elsif ciclo[:pegou]
      { situacao: 'atendimento', segundos_na_situacao: segundos(ciclo[:pegou].encerrado_em, agora) }
    elsif fim_perdido?(ciclo[:elos])
      { situacao: 'perdido', segundos_na_situacao: 0 }
    else
      { situacao: 'espera', segundos_na_situacao: segundos(ultimo.designado_em || ultimo.created_at, agora) }
    end
  end

  def identificacao(log, elos)
    contato = log.conversation&.contact
    {
      # A chave do v-for: a mesma CONVERSA se repete quando o contato volta em outro ciclo.
      id: log.id,
      conversation_id: log.conversation_id,
      display_id: log.conversation&.display_id,
      # Quem é o lead, na linguagem de quem lê a tela: o número identifica mais rápido que o #id.
      contato: contato&.name,
      telefone: contato&.phone_number,
      # Com quem o lead está AGORA (o último da cadeia de repasses).
      corretor: nome(elos.last),
      pessoas: elos.filter_map(&:chosen_user_id).uniq,
      canal: canal(log),
      produto: log.produto_slug
    }
  end

  # Os marcos do rastreio, em ordem. Cada um diz o que aconteceu, com quem e quando; a tela
  # escreve a duração entre um e outro no conector.
  def eventos(ciclo)
    lista = [{ tipo: 'chegou', em: ciclo[:chegou] }, { tipo: 'designado', em: ciclo[:designado], quem: nome(ciclo[:elos].first) }]
    lista += repasses(ciclo[:elos]) + desfecho(ciclo)
    lista.select { |evento| evento[:em] }.each_with_index.sort_by { |evento, ordem| [evento[:em], ordem] }.map(&:first)
  end

  def repasses(elos)
    elos.each_cons(2).map do |anterior, seguinte|
      { tipo: 'repassado', em: seguinte.designado_em || anterior.encerrado_em, quem: nome(seguinte), de: nome(anterior),
        motivo: seguinte.motivo, status_anterior: anterior.status }
    end
  end

  def desfecho(ciclo)
    ultimo = ciclo[:elos].last
    pegou = ciclo[:pegou]
    resposta = primeira_resposta(ciclo)
    [
      ({ tipo: 'expirou', em: ultimo.encerrado_em, quem: nome(ultimo), status_anterior: ultimo.status } if fim_perdido?(ciclo[:elos])),
      ({ tipo: 'pegou', em: pegou.encerrado_em, quem: nome(pegou) } if pegou),
      ({ tipo: 'respondeu', em: resposta } if resposta),
      ({ tipo: 'resolvido', em: ciclo[:resolvido_em], quem: ciclo[:resolvido_por] } if ciclo[:resolvido_em])
    ].compact
  end

  # `first_reply_created_at` é da CONVERSA, não do ciclo: no contato que volta ele é de semanas
  # atrás. Só entra na linha se caiu dentro deste ciclo.
  def primeira_resposta(ciclo)
    instante = ciclo[:log].conversation&.first_reply_created_at
    instante if instante && instante >= ciclo[:chegou] && (ciclo[:fim].nil? || instante < ciclo[:fim])
  end

  def nome(elo)
    nomes[elo.chosen_user_id]
  end

  def canal(log)
    tipo = log.conversation&.inbox&.channel_type.to_s
    @canais[tipo] || tipo.presence || '—'
  end
end
