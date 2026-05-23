class Captain::Tools::Copilot::GetConversationAnalysisService < Captain::Tools::BaseTool
  def self.name
    'get_conversation_analysis'
  end
  description <<~DESC.squish
    Consulta a análise agregada das conversas de atendimento já avaliadas pelo
    sistema de eval (LLM-as-a-Judge): nível de interesse, intenção predominante
    (locação/venda/etc), estágio do funil, principais objeções, falhas mais comuns
    dos agentes por persona e qualidade/timing dos handoffs para humano. Use quando
    o gestor perguntar sobre desempenho, qualidade, gargalos ou padrões dos
    atendimentos — tanto da IA quanto dos humanos.
  DESC

  def execute
    token = eval_api_token
    return 'Análise indisponível: token do serviço de eval não configurado.' if token.blank?

    response = HTTParty.get(eval_api_url, headers: { 'Authorization' => "Bearer #{token}" }, timeout: 10)
    return "Análise indisponível no momento (HTTP #{response.code})." unless response.code == 200

    format_report(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.warn("[Copilot] get_conversation_analysis falhou: #{e.message}")
    'Análise indisponível no momento.'
  end

  def active?
    return false unless @assistant.account_id == eval_account_id

    user_has_permission('report_manage')
  end

  private

  def eval_api_url
    ENV.fetch('TOZI_EVAL_API_URL', 'http://127.0.0.1:8910/report')
  end

  def eval_api_token
    ENV['TOZI_EVAL_API_TOKEN'].presence || InstallationConfig.find_by(name: 'TOZI_EVAL_API_TOKEN')&.value
  end

  def eval_account_id
    ENV.fetch('TOZI_EVAL_ACCOUNT_ID', '1').to_i
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
