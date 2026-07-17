# Agregados do eval (Eval 2.0 F4) pro painel "Avaliação" do módulo Agentes IA.
# Read-only, defensivo (nunca 500 — seção com erro volta vazia) e por conta.
class Api::V1::Accounts::Captain::EvalDashboardController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  def show
    base = Captain::ConversationEval.for_account(Current.account.id)
    evals = base.por_episodio.exists? ? base.por_episodio : base
    escopo = evals.em_escopo

    render json: {
      unit: base.por_episodio.exists? ? 'episode' : 'conversation',
      enabled: Captain::ConversationEval.enabled_for?(Current.account),
      totals: totals(evals, escopo),
      nota: nota_stats(escopo),
      funil: safe_group(escopo, :funil),
      handoff: safe_group(escopo, :handoff_timing),
      fronteiras: fronteiras,
      findings: findings_stats(escopo),
      recentes: recentes(evals)
    }
  end

  private

  def totals(evals, escopo)
    episodes = Captain::ConversationEpisode.for_account(Current.account.id)
    {
      julgados: evals.count,
      em_escopo: escopo.count,
      fora_de_escopo: evals.count - escopo.count,
      episodios: episodes.count,
      episodios_abertos: episodes.open_ones.count,
      conversas: episodes.distinct.count(:conversation_id),
      conversas_multi: episodes.group(:conversation_id).count.values.count { |v| v >= 2 }
    }
  rescue StandardError
    {}
  end

  def nota_stats(escopo)
    com_nota = escopo.where.not(nota: nil)
    dist = { '0-4' => 0, '5-6' => 0, '7-8' => 0, '9-10' => 0 }
    com_nota.pluck(:nota).each do |n|
      dist[n <= 4 ? '0-4' : (n <= 6 ? '5-6' : (n <= 8 ? '7-8' : '9-10'))] += 1
    end
    { media: com_nota.average(:nota)&.round(2), dist: dist }
  rescue StandardError
    {}
  end

  def safe_group(scope, column)
    scope.where.not(column => nil).group(column).count
  rescue StandardError
    {}
  end

  def fronteiras
    Captain::ConversationEpisode.for_account(Current.account.id).closed.group(:boundary_reason).count
  rescue StandardError
    {}
  end

  def findings_stats(escopo)
    ia = 0
    humano = 0
    gate = 0
    categorias = Hash.new(0)
    escopo.recent.limit(1000).pluck(:response_findings).each do |findings|
      Array(findings).each do |f|
        next unless f.is_a?(Hash)

        f['quem'] == 'humano' ? humano += 1 : ia += 1
        gate += 1 if f['origem'] == 'gate'
        categorias[f['categoria']] += 1 if f['categoria'].present?
      end
    end
    { ia: ia, humano: humano, gate: gate, top: categorias.sort_by { |_, v| -v }.first(8).map { |k, v| { categoria: k, count: v } } }
  rescue StandardError
    {}
  end

  def recentes(evals)
    rows = evals.recent.limit(20).to_a
    episode_ids = rows.filter_map(&:episode_id)
    episodes = Captain::ConversationEpisode.where(id: episode_ids).index_by(&:id)
    totals_by_conv = Captain::ConversationEpisode.where(conversation_id: rows.map(&:conversation_id).uniq)
                                                 .group(:conversation_id).count
    display_ids = Conversation.where(id: rows.map(&:conversation_id).uniq).pluck(:id, :display_id).to_h

    rows.map do |ev|
      episode = episodes[ev.episode_id]
      {
        conversation_display_id: display_ids[ev.conversation_id],
        episode_seq: episode&.seq,
        episode_total: totals_by_conv[ev.conversation_id],
        boundary_reason: episode&.boundary_reason,
        nota: ev.nota,
        intencao: ev.intencao,
        funil: ev.funil,
        handoff_timing: ev.handoff_timing,
        conduzido_por: ev.conduzido_por,
        representatividade: ev.representatividade,
        resumo: ev.resumo.to_s[0, 180],
        avaliado_em: ev.avaliado_em
      }
    end
  rescue StandardError
    []
  end
end
