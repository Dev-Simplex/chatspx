# Agregados do eval (Eval 2.0 F4) pro painel "Avaliação" do módulo Agentes IA.
# Read-only, defensivo (nunca 500 — seção com erro volta vazia) e por conta.
class Api::V1::Accounts::Captain::EvalDashboardController < Api::V1::Accounts::BaseController
  before_action :current_account
  # authorize com query fixa :show? — check_authorization derivaria "episodes?",
  # que não existe na AssistantPolicy (Pundit::NotDefinedError → 500)
  before_action -> { authorize(Captain::Assistant, :show?) }

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
      recentes: recentes(evals),
      saude: saude
    }
  end

  # Drill-down por indicador (F4.1): lista os episódios julgados que compõem um
  # número do painel. Filtros combináveis: nota_faixa, funil, handoff_timing,
  # categoria (+quem), escopo=ruido. Com categoria, devolve a evidência (trecho
  # do finding que casou).
  def episodes
    base = Captain::ConversationEval.for_account(Current.account.id)
    evals = base.por_episodio.exists? ? base.por_episodio : base
    evals = apply_filters(evals)
    render json: {
      rows: serialize_rows(evals.recent.limit(50).to_a,
                           matched_categoria: params[:categoria].presence,
                           matched_quem: params[:quem].presence)
    }
  rescue StandardError
    render json: { rows: [] }
  end

  # F4.2 (Eval humano): episódios de UMA conversa, pro modal "Avaliar atendimento"
  # — o gestor vê os ciclos de atendimento da conversa perpétua e escolhe qual avaliar.
  def conversation_episodes
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_display_id])
    episodes = Captain::ConversationEpisode.where(conversation_id: conversation.id).order(seq: :desc).limit(30).to_a
    evals = Captain::ConversationEval.where(episode_id: episodes.map(&:id)).index_by(&:episode_id)
    render json: {
      episodes: episodes.map do |ep|
        ev = evals[ep.id]
        {
          id: ep.id,
          seq: ep.seq,
          started_at: ep.started_at,
          ended_at: ep.ended_at,
          mensagens: ep.mensagens,
          nota: ev&.nota,
          conduzido_por: ev&.conduzido_por,
          resumo: ev&.resumo.to_s.truncate(160).presence,
          anotacoes: ep.human_annotations.count
        }
      end
    }
  end

  # F4.2: registra a avaliação do gestor como nota privada #eval ANCORADA no episódio
  # escolhido (content_attributes.eval_episode_id — sem adivinhação temporal). A criação
  # da mensagem dispara o CaptainListener, que re-julga o episódio se já fechado.
  def annotate
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_display_id])
    episode = Captain::ConversationEpisode.find_by!(id: params[:episode_id], conversation_id: conversation.id)
    texto = params[:texto].to_s.strip
    return render json: { error: 'texto vazio' }, status: :unprocessable_entity if texto.blank?

    conversation.messages.create!(
      account_id: Current.account.id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: Current.user,
      content: "#eval #{texto}",
      content_attributes: { eval_episode_id: episode.id }
    )
    render json: { ok: true, episode_id: episode.id, pending: episode.ended_at.blank? }
  end

  private

  NOTA_FAIXAS = { '0-4' => 0..4, '5-6' => 5..6, '7-8' => 7..8, '9-10' => 9..10 }.freeze

  def apply_filters(scope)
    scope = if params[:escopo] == 'ruido'
              scope.where.not(representatividade: 'atendimento_real')
            else
              scope.em_escopo
            end
    scope = scope.where(funil: params[:funil]) if params[:funil].present?
    scope = scope.where(handoff_timing: params[:handoff_timing]) if params[:handoff_timing].present?
    scope = scope.where(nota: NOTA_FAIXAS[params[:nota_faixa]]) if NOTA_FAIXAS.key?(params[:nota_faixa])
    scope = filter_by_finding(scope)
    scope
  end

  # jsonb containment: acha evals cujo response_findings contém um finding com
  # a categoria (e opcionalmente o autor) pedidos.
  def filter_by_finding(scope)
    if params[:categoria].present?
      cond = { 'categoria' => params[:categoria] }
      cond['quem'] = params[:quem] if params[:quem].present?
      scope.where('response_findings @> ?', [cond].to_json)
    elsif params[:quem].present?
      scope.where('response_findings @> ?', [{ 'quem' => params[:quem] }].to_json)
    else
      scope
    end
  end

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

  # Sinais vitais do pipeline pro painel: as panes do eval são silenciosas por
  # natureza — o gestor precisa VER que o julgamento está vivo (ou parado).
  def saude
    epi = Captain::ConversationEval.for_account(Current.account.id).por_episodio
    {
      ultimo_julgamento_em: epi.maximum(:avaliado_em),
      julgados_24h: epi.where('avaliado_em >= ?', 24.hours.ago).count,
      fechados_24h: Captain::ConversationEpisode.for_account(Current.account.id)
                                                .where('ended_at >= ?', 24.hours.ago).count
    }
  rescue StandardError
    {}
  end

  def findings_stats(escopo)
    ia = 0
    humano = 0
    gate = 0
    categorias = Hash.new { |hash, key| hash[key] = { count: 0, ia: 0, humano: 0 } }
    escopo.recent.limit(1000).pluck(:response_findings).each do |findings|
      Array(findings).each do |f|
        next unless f.is_a?(Hash)

        de_humano = f['quem'] == 'humano'
        de_humano ? humano += 1 : ia += 1
        gate += 1 if f['origem'] == 'gate'
        next if f['categoria'].blank?

        cat = categorias[f['categoria']]
        cat[:count] += 1
        de_humano ? cat[:humano] += 1 : cat[:ia] += 1
      end
    end
    top = categorias.sort_by { |_, v| -v[:count] }.first(8).map { |k, v| { categoria: k, **v } }
    { ia: ia, humano: humano, gate: gate, top: top }
  rescue StandardError
    {}
  end

  def recentes(evals)
    serialize_rows(evals.recent.limit(20).to_a)
  rescue StandardError
    []
  end

  def serialize_rows(rows, matched_categoria: nil, matched_quem: nil)
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
        avaliado_em: ev.avaliado_em,
        findings_matched: matched_findings(ev, matched_categoria, matched_quem)
      }
    end
  end

  # Evidência do drill-down: os findings do eval que casaram com o filtro.
  def matched_findings(evaluation, categoria, quem)
    return [] if categoria.blank? && quem.blank?

    Array(evaluation.response_findings).select do |f|
      next false unless f.is_a?(Hash)

      (categoria.blank? || f['categoria'] == categoria) && (quem.blank? || f['quem'] == quem)
    end.first(3).map do |f|
      { quem: f['quem'], severidade: f['severidade'], trecho: f['trecho'].to_s[0, 140], porque: f['porque'].to_s[0, 160] }
    end
  end
end
