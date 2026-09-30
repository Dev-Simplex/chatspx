# CHAT-177: a matematica do ranking, sem banco.
#
# Percentual por indicador: maior-e-melhor -> realizado / meta (realizado negativo, caso do NPS, conta 0);
# menor-e-melhor (primeira resposta) -> meta / realizado. Sem meta OU sem dado -> nil: o indicador fica fora
# da nota daquela linha, nunca vira 0%.
# Nota geral: media simples dos percentuais presentes, cada um limitado a 150% DENTRO da media (a coluna
# mostra o percentual sem limite). O teto impede que um indicador de meta baixa esconda os outros.
module PerformanceGoals::Scoring
  CAP = 1.5

  module_function

  def attainment(metric, actual, goal)
    return if actual.nil? || goal.nil? || goal.to_f <= 0
    return goal.to_f / actual if PerformanceGoal::LOWER_IS_BETTER.include?(metric) && actual.to_f.positive?
    return CAP if PerformanceGoal::LOWER_IS_BETTER.include?(metric) # resposta instantanea: o teto basta

    [actual.to_f, 0].max / goal.to_f
  end

  def overall(attainments)
    present = attainments.compact
    return if present.empty?

    present.sum { |value| [value, CAP].min } / present.size
  end

  # rows: [{ id:, name:, metrics: { metric => { actual:, goal: } } }]. Devolve [ranqueadas, sem_meta]: preenche
  # attainment/overall/position. Sem meta nenhuma -> bloco "Sem meta definida". Ordem: nota geral (maior
  # primeiro); empate -> mais conversas resolvidas, depois nome. Com meta mas sem dado nenhum -> no fim.
  def rank(rows)
    scored = rows.map { |row| score_row(row) }
    with_goal, without_goal = scored.partition { |row| row[:metrics].values.any? { |m| m[:goal] } }
    ranked = with_goal.sort_by { |row| sort_key(row) }
    ranked.each_with_index { |row, index| row[:position] = index + 1 }
    [ranked, without_goal.sort_by { |row| row[:name].to_s.downcase }]
  end

  def score_row(row)
    metrics = row[:metrics].to_h do |metric, data|
      [metric, data.merge(attainment: attainment(metric, data[:actual], data[:goal]))]
    end
    row.merge(metrics: metrics, overall: overall(metrics.values.pluck(:attainment)))
  end

  def sort_key(row)
    resolved = row.dig(:metrics, 'resolved_conversations', :actual).to_f
    [row[:overall] ? 0 : 1, -row[:overall].to_f, -resolved, row[:name].to_s.downcase]
  end
end
