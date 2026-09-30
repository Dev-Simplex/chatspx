# frozen_string_literal: true

# Resumo do rodízio em linguagem de GESTOR: quatro números que respondem "está indo bem?" sem
# ninguém precisar interpretar tabela.
#
# Fonte única da tela e do PDF. O veredito (verde/amarelo/vermelho) sai daqui estruturado, nunca
# como texto traduzido — a frase é montada no front (i18n) ou no template do PDF, que é a regra
# de ouro dos relatórios auto-explicativos deste fork.
#
# A META NÃO É INVENTADA: o alvo do tempo de espera é o **SLA que o próprio cliente configurou**
# na política do time (`sla_assumir_minutos`). Cobrar 5 minutos de quem combinou 30 seria pintar
# de vermelho um time que está cumprindo o combinado.
class Spx::Distribuicao::ResumoService
  ASSUMIDOS = %w[assumido engajado].freeze
  # `substituido` é repasse — o lead seguiu para outra pessoa, não se perdeu. Só `expirado` é
  # lead que ninguém pegou até o prazo acabar.
  PERDIDO = 'expirado'
  SLA_PADRAO_MINUTOS = 30

  # `recorte` é o mesmo Spx::Distribuicao::Recorte da tela e do PDF (time, agente, canal, produto).
  def initialize(account:, inicio:, fim:, recorte: nil, comparar: false)
    @account = account
    @de = inicio
    @ate = fim
    @recorte = recorte || Spx::Distribuicao::Recorte.new(account: account)
    # Comparar custa um segundo passe no livro-razão. A TELA recarrega sozinha e não usa o delta,
    # então o padrão é não comparar; quem pede é o PDF, que roda em job.
    @comparar = comparar
  end

  def call
    {
      sla_minutos: sla_minutos,
      recebidos: recebidos,
      pelo_rodizio: do_rodizio.size,
      assumidos: assumidos.size,
      espera_media_segundos: espera_media,
      no_prazo: no_prazo,
      no_prazo_pct: percentual(no_prazo, assumidos.size),
      parados_agora: parados_agora,
      parados_pct: percentual(parados_agora, recebidos),
      expirados: expirados,
      expirados_pct: percentual(expirados, do_rodizio.size),
      anterior: anterior.slice(:recebidos, :espera_media_segundos, :no_prazo_pct, :expirados_pct),
      signals: sinais
    }
  end

  # O limiar do "parado" é o mesmo SLA: menor `sla_assumir_minutos` entre as políticas ativas
  # (do time, quando filtrado). É o número que o cliente combinou, não um padrão nosso. O agente
  # não mexe na meta: o prazo é do time, e o agente é cobrado pelo mesmo número que os colegas.
  def sla_minutos
    @sla_minutos ||= begin
      escopo = Spx::Distribuicao::Policy.where(account_id: @account.id, ativo: true)
      escopo = escopo.where(team_id: @recorte.team_id) if @recorte.team_id
      escopo.where.not(sla_assumir_minutos: nil).minimum(:sla_assumir_minutos) || SLA_PADRAO_MINUTOS
    end
  end

  # "Pega em X min" por consultor: a mesma espera do cartão, agrupada por quem recebeu — uma query,
  # não uma por linha. { user_id => segundos }.
  def espera_por_consultor
    assumidos.group(:chosen_user_id)
             .average(Arel.sql('EXTRACT(EPOCH FROM (encerrado_em - designado_em))'))
             .transform_values { |media| media&.to_f&.round }
  end

  # "Parado AGORA" ignora o período de propósito: o que interessa ao gestor é o que está parado
  # neste instante, inclusive lead designado no mês passado. O prazo já passou em todos — é a
  # régua do cartão.
  #
  # Público porque o PDF LISTA quem são: um cartão dizendo "6 parados" e uma lista com 4 nomes
  # seria o gestor conferindo a conta e não fechando (o `motivo` não entra aqui de propósito —
  # lead repassado por estouro de prazo também está parado esperando alguém).
  def escopo_parados
    @escopo_parados ||= @recorte.aplicar(Spx::Distribuicao::Log.where(account_id: @account.id, status: 'designado')
                                               .where(designado_em: ..sla_minutos.minutes.ago))
  end

  # Veredito de UMA espera (a de um consultor) com a mesma régua do cartão. Nil sem média.
  def sinal_de_espera(media)
    return nil if media.nil?

    Reports::SignalSet.new(entries: [{ metric: :rodizio_espera, value: media }], benchmarks: metas.slice(:rodizio_espera)).build.first
  end

  private

  def periodo
    @periodo ||= @recorte.aplicar(Spx::Distribuicao::Log.where(account_id: @account.id, created_at: @de..@ate))
  end

  # Mesmo recorte da tela: só decisão COM corretor é lead recebido (`sem_pool` é auditoria).
  def recebidos
    @recebidos ||= periodo.where.not(chosen_user_id: nil).count
  end

  # Espera só faz sentido para quem passou pela FILA. Continuidade e pedido do cliente já nascem
  # com dono; medir a espera deles inventaria um problema que não existe.
  def do_rodizio
    @do_rodizio ||= periodo.where(motivo: 'rodizio').where.not(chosen_user_id: nil)
  end

  def assumidos
    @assumidos ||= do_rodizio.where(status: ASSUMIDOS).where.not(designado_em: nil).where.not(encerrado_em: nil)
  end

  def espera_media
    media = assumidos.pick(Arel.sql('AVG(EXTRACT(EPOCH FROM (encerrado_em - designado_em)))'))
    media&.to_f&.round
  end

  def no_prazo
    @no_prazo ||= assumidos.where('encerrado_em - designado_em <= ?', "#{sla_minutos} minutes").count
  end

  def parados_agora
    @parados_agora ||= escopo_parados.count
  end

  def expirados
    @expirados ||= do_rodizio.where(status: PERDIDO).count
  end

  def percentual(parte, total)
    return nil if total.to_i.zero?

    ((parte.to_f / total) * 100).round
  end

  # As metas: tempo de espera contra o SLA combinado; o resto em percentual, com a régua escrita
  # aqui e em lugar nenhum mais.
  def metas
    alvo = sla_minutos * 60
    {
      rodizio_espera: { goal: alvo, green: alvo, yellow: alvo * 2, lower_better: true },
      rodizio_no_prazo: { goal: 90, green: 90, yellow: 70, lower_better: false },
      rodizio_parados: { goal: 5, green: 5, yellow: 15, lower_better: true },
      rodizio_expirados: { goal: 0, green: 0, yellow: 5, lower_better: true }
    }
  end

  # Período anterior de MESMA duração, para o gestor saber se melhorou ou piorou. O SignalSet já
  # sabe calcular `delta_pct` quando a entrada traz `prev` — até agora ninguém alimentava esse
  # campo, então o documento dizia o número sem dizer a direção.
  #
  # "Parados agora" fica de fora da comparação de propósito: é uma foto do instante, não do
  # período; comparar com "os parados de um mês atrás" não significa nada.
  def anterior
    return {} unless @comparar

    @anterior ||= begin
      duracao = @ate - @de
      self.class.new(account: @account, inicio: @de - duracao, fim: @de,
                     recorte: @recorte, comparar: false).call
    rescue StandardError
      {}
    end
  end

  def sinais
    entradas = [
      { metric: :rodizio_espera, value: espera_media, prev: anterior[:espera_media_segundos] },
      { metric: :rodizio_no_prazo, value: no_prazo_pct_bruto, prev: anterior[:no_prazo_pct] },
      { metric: :rodizio_parados, value: percentual(parados_agora, recebidos) },
      { metric: :rodizio_expirados, value: percentual(expirados, do_rodizio.size), prev: anterior[:expirados_pct] }
    ].reject { |e| e[:value].nil? }

    Reports::SignalSet.new(entries: entradas, benchmarks: metas).build
  end

  def no_prazo_pct_bruto
    percentual(no_prazo, assumidos.size)
  end
end
