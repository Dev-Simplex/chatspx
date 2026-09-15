# Linha do tempo dos leads que caíram num consultor PELO RODÍZIO (SPEC-RODIZIO §9).
#
# A tela de contabilização diz QUANTOS cada um recebeu. Isto diz o que aconteceu com cada lead:
# quanto tempo a IA cobriu antes de o motor escolher alguém, quanto o lead esperou o escolhido
# pegar, e quanto durou o atendimento. Read-only: lê o livro-razão, não decide nada.
#
# Só `motivo: rodizio` de propósito. Continuidade e pedido do cliente não passaram pela fila —
# medir a espera deles como se fosse rodízio inventaria um problema que não existe.
class Spx::Distribuicao::LinhaDoTempoService
  # Teto da faixa, igual ao do drill-down por conversa. O total sem teto vai junto na resposta,
  # para a tela poder dizer "mostrando 20 de 34".
  LIMITE = 20
  # Designação que fechou porque alguém ENCOSTOU no lead: é o fim da espera.
  ASSUMIDOS = %w[assumido engajado].freeze
  # Fechou sem ninguém encostar: o lead foi embora para outro corretor.
  PERDIDOS = %w[expirado substituido].freeze

  # Quem ainda espera vem PRIMEIRO, do que espera há mais tempo. Sem isto o teto cortava
  # justamente o lead parado — ele é antigo por definição, e a ordem por data de designação o
  # empurrava para o fim. O que já terminou vem do mais recente.
  ORDEM = Arel.sql(
    '(encerrado_em IS NULL) DESC, ' \
    'CASE WHEN encerrado_em IS NULL THEN designado_em END ASC NULLS LAST, ' \
    'designado_em DESC NULLS LAST, id DESC'
  )

  # `escopo` chega pronto do controller (conta + período + time), para o recorte da faixa ser
  # exatamente o mesmo da tabela em volta. Sem `user_id` a lista é da conta inteira — é a aba
  # "Leads", que responde "onde está cada um" sem precisar adivinhar em quem ele caiu.
  def initialize(escopo:, canais: {}, user_id: nil, limite: LIMITE)
    @escopo = escopo.where(motivo: 'rodizio')
    @escopo = @escopo.where(chosen_user_id: user_id) if user_id.present?
    @canais = canais
    @limite = limite
  end

  def call
    {
      leads: ordenar(logs.map { |log| serializar(log) }),
      total: @escopo.count,
      media_espera_segundos: media_espera_segundos
    }
  end

  private

  def logs
    @logs ||= @escopo.includes(:chosen_user, conversation: [:inbox, :contact])
                     .order(ORDEM)
                     .limit(@limite)
                     .to_a
  end

  # Três grupos, na ordem em que a gestão precisa olhar: ninguém pegou, está em atendimento, já
  # terminou. Dentro dos dois primeiros, quem está há mais tempo assim aparece antes. O SQL já
  # traz os parados; aqui separa quem está em atendimento de quem terminou, que só se sabe
  # depois de cruzar com a resolução.
  def ordenar(leads)
    leads.sort_by do |lead|
      case lead[:situacao]
      when 'espera' then [0, -lead[:segundos_na_situacao]]
      when 'atendimento' then [1, -lead[:segundos_na_situacao]]
      else [2, -lead[:designado_em].to_i]
      end
    end
  end

  def conversation_ids
    @conversation_ids ||= logs.map(&:conversation_id)
  end

  # Média só de quem foi assumido: designação ainda aberta não tem espera final, e contá-la
  # como se tivesse acabado agora empurraria a média para cima a cada recarga da tela.
  #
  # Os dois `where.not` são separados de propósito: `where.not(a: nil, b: nil)` vira
  # NOT (a IS NULL AND b IS NULL), que deixa passar a linha em que só uma das duas é nula.
  def media_espera_segundos
    @escopo.where(status: ASSUMIDOS)
           .where.not(designado_em: nil)
           .where.not(encerrado_em: nil)
           .average(Arel.sql('EXTRACT(EPOCH FROM (encerrado_em - designado_em))'))
           &.round
  end

  # `conversation_resolved` é o único lugar com hora de resolução: `conversations` guarda só o
  # status atual. O contato que volta cai na MESMA conversa, com um evento por ciclo: vale o
  # primeiro depois desta designação. O último da vida da conversa pode ser de um ciclo anterior
  # (e o lead que ainda espera apareceria resolvido) ou do seguinte (e o atendimento incharia).
  def resolvidos_em
    @resolvidos_em ||= ReportingEvent.where(name: 'conversation_resolved', conversation_id: conversation_ids)
                                     .pluck(:conversation_id, :event_end_time)
                                     .group_by(&:first)
                                     .transform_values { |pares| pares.filter_map(&:last).sort }
  end

  def resolucao(log, designado)
    (resolvidos_em[log.conversation_id] || []).find { |instante| instante >= designado }
  end

  # Quando a conversa REABRIU. No WhatsApp o contato que volta cai na mesma conversa, então
  # `conversations.created_at` pode ser de semanas atrás: sem isto, a fase "IA cobrindo" de um
  # lead redistribuído hoje traria o tempo inteiro desde a primeira mensagem da vida do contato
  # (medido: 24 dias) e esmagaria a espera, que é o que esta tela existe para mostrar.
  def reaberturas_em
    @reaberturas_em ||= ReportingEvent.where(name: 'conversation_opened', conversation_id: conversation_ids)
                                      .pluck(:conversation_id, :event_end_time)
                                      .group_by(&:first)
                                      .transform_values { |pares| pares.filter_map(&:last).sort }
  end

  # A chegada DESTE lead: a última reabertura antes de o motor designar, ou o nascimento da
  # conversa quando ela nunca reabriu.
  def chegada(log, designado)
    reaberturas = reaberturas_em[log.conversation_id] || []
    reaberturas.reverse.find { |instante| instante <= designado } || log.conversation&.created_at || designado
  end

  # Todas as designações das mesmas conversas, para achar PARA QUEM o lead foi quando esta
  # aqui expirou. Uma query só: a busca do sucessor acontece em memória.
  def designacoes_por_conversa
    @designacoes_por_conversa ||= Spx::Distribuicao::Log.where(conversation_id: conversation_ids)
                                                        .includes(:chosen_user)
                                                        .order(:id)
                                                        .group_by(&:conversation_id)
  end

  def sucessor(log)
    designacoes_por_conversa.fetch(log.conversation_id, []).find { |outra| outra.id > log.id }
  end

  # Duração nunca negativa: relógio torto ou dado antigo não pode virar bloco de largura
  # negativa na barra.
  def segundos(inicio, fim)
    return 0 if inicio.blank? || fim.blank?

    [(fim - inicio).round, 0].max
  end

  def serializar(log)
    marcos = marcos(log)
    fases = fases(marcos)
    identificacao(log).merge(marcos).merge(fases).merge(desfecho(log, marcos)).merge(situacao(marcos, fases[:fases]))
  end

  # Onde o lead está AGORA, e há quanto tempo — é o que a tela mostra no selo ("esperando Emily
  # pegar há 38 min"). Sai daqui, e não da tela, para o selo e a ORDEM da lista nunca discordarem.
  def situacao(marcos, fases)
    return { situacao: 'espera', segundos_na_situacao: fases[:espera] } if aguardando?(marcos)
    return { situacao: 'atendimento', segundos_na_situacao: fases[:atendimento] } if em_curso?(marcos)

    { situacao: 'encerrado', segundos_na_situacao: 0 }
  end

  # Ninguém encostou: nem pegou, nem perdeu para outro. É a espera que ainda corre.
  def aguardando?(marcos)
    marcos[:assumido_em].blank? && marcos[:perdido_em].blank?
  end

  def em_curso?(marcos)
    marcos[:assumido_em].present? && marcos[:resolvido_em].blank?
  end

  def identificacao(log)
    contato = log.conversation&.contact
    {
      conversation_id: log.conversation_id,
      display_id: log.conversation&.display_id,
      # Quem é o lead, na linguagem de quem lê a tela: o número identifica mais rápido que o #id.
      contato: contato&.name,
      telefone: contato&.phone_number,
      # O corretor desta designação: é o dono da espera e do atendimento na barra.
      corretor: log.chosen_user&.name,
      canal: canal(log),
      produto: log.produto_slug,
      status: log.status,
      repasse_n: log.repasse_n
    }
  end

  def marcos(log)
    conversa = log.conversation
    designado = log.designado_em || log.created_at
    {
      chegou_em: chegada(log, designado),
      designado_em: designado,
      assumido_em: (log.encerrado_em if ASSUMIDOS.include?(log.status)),
      perdido_em: (log.encerrado_em if PERDIDOS.include?(log.status)),
      primeira_resposta_em: conversa&.first_reply_created_at,
      resolvido_em: resolucao(log, designado)
    }
  end

  # Os três blocos da barra. `espera` corre até agora enquanto ninguém pega — é o único que
  # fica crescendo na tela, e é o que o rodízio de fato controla.
  def fases(marcos)
    agora = Time.zone.now
    ia = segundos(marcos[:chegou_em], marcos[:designado_em])
    espera = segundos(marcos[:designado_em], marcos[:assumido_em] || marcos[:perdido_em] || agora)
    atendimento = marcos[:assumido_em] ? segundos(marcos[:assumido_em], marcos[:resolvido_em] || agora) : 0

    { fases: { ia: ia, espera: espera, atendimento: atendimento },
      total_segundos: ia + espera + atendimento }
  end

  def desfecho(log, marcos)
    {
      em_curso: em_curso?(marcos),
      repassado_para: marcos[:perdido_em] && sucessor(log)&.chosen_user&.name
    }
  end

  def canal(log)
    tipo = log.conversation&.inbox&.channel_type.to_s
    @canais[tipo] || tipo.presence || '—'
  end
end
