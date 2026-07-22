class Captain::Tools::Copilot::GetConversationAnalysisService < Captain::Tools::BaseTool
  # Amostra dos evals mais recentes para os agregados sobre jsonb (objeções/falhas),
  # evitando varrer a conta inteira em contas com muito histórico.
  SAMPLE_LIMIT = 1000

  def self.name
    'get_conversation_analysis'
  end
  description <<~DESC.squish
    Consulta a análise agregada dos atendimentos já avaliados pelo sistema de eval
    (LLM-as-a-Judge): nível de interesse, intenção predominante (locação/venda/etc),
    estágio do funil, principais objeções, falhas mais comuns dos agentes por persona
    e qualidade/timing dos handoffs para humano. Use quando o gestor perguntar sobre
    desempenho, qualidade, gargalos ou padrões dos atendimentos — tanto da IA quanto
    dos humanos.
  DESC

  def execute
    evals = Captain::ConversationEval.for_account(@assistant.account_id)
    total = evals.count
    return 'Ainda não há conversas avaliadas pelo eval.' if total.zero?

    format_report(build_report(evals, total))
  rescue StandardError => e
    Rails.logger.warn("[Copilot] get_conversation_analysis falhou: #{e.message}")
    'Análise indisponível no momento.'
  end

  def active?
    return false unless Captain::ConversationEval.enabled_for?(@assistant.account)

    user_has_permission('report_manage')
  end

  private

  def build_report(evals, total)
    {
      'total_conversas' => total,
      'interesse' => evals.where.not(interesse: nil).group(:interesse).count,
      'intencao' => evals.where.not(intencao: nil).group(:intencao).count,
      'funil' => evals.where.not(funil: nil).group(:funil).count,
      'handoff_timing' => evals.where.not(handoff_timing: nil).group(:handoff_timing).count,
      'falhas_por_agente' => falhas_por_agente(evals),
      'top_objecoes' => top_from_jsonb(evals, :objecoes),
      'top_falhas' => top_falhas(evals)
    }
  end

  def sampled(evals)
    evals.recent.limit(SAMPLE_LIMIT)
  end

  def falhas_por_agente(evals)
    counts = Hash.new(0)
    sampled(evals).pluck(:captain_assistant_id, :response_findings).each do |assistant_id, findings|
      counts[assistant_id] += Array(findings).size
    end
    counts.reject { |_, total| total.zero? }.transform_keys { |id| assistant_name(id) }
  end

  def top_falhas(evals)
    counts = Hash.new(0)
    sampled(evals).pluck(:response_findings).each do |findings|
      Array(findings).each { |f| counts[f['categoria']] += 1 if f.is_a?(Hash) && f['categoria'].present? }
    end
    counts.sort_by { |_, n| -n }.first(8)
  end

  def top_from_jsonb(evals, column)
    counts = Hash.new(0)
    sampled(evals).pluck(column).each do |items|
      Array(items).each { |item| counts[item.to_s] += 1 if item.present? }
    end
    counts.sort_by { |_, n| -n }.first(8)
  end

  def assistant_name(id)
    return 'sem agente' if id.blank?

    @assistant_names ||= {}
    @assistant_names[id] ||= Captain::Assistant.find_by(id: id)&.name || "agente ##{id}"
  end

  def format_report(data)
    total = data['total_conversas'].to_i
    return 'Ainda não há conversas avaliadas pelo eval.' if total.zero?

    lines = ["Análise de #{total} conversa(s) avaliada(s):"]
    lines << "- Interesse: #{fmt_hash(data['interesse'])}"
    lines << "- Intenção: #{fmt_hash(data['intencao'])}"
    lines << "- Funil: #{fmt_hash(data['funil'])}"
    lines << "- Falhas por agente: #{fmt_hash(data['falhas_por_agente'])}"
    lines << "- Handoff timing: #{fmt_hash(data['handoff_timing'])}"
    lines << "- Principais objeções: #{fmt_pairs(data['top_objecoes'])}"
    lines << "- Principais falhas dos agentes: #{fmt_pairs(data['top_falhas'])}"
    lines.join("\n")
  end

  def fmt_hash(hash)
    return 'sem dados' if hash.blank?

    hash.map { |k, v| "#{k}: #{v}" }.join(', ')
  end

  def fmt_pairs(pairs)
    return 'sem dados' if pairs.blank?

    pairs.map { |cat, n| "#{cat} (#{n})" }.join(', ')
  end
end
