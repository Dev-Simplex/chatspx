# Constrói os signals (semáforo) de UMA linha dos relatórios de resumo por entidade
# (agente/caixa/time/etiqueta). Cada linha traz as mesmas métricas de Conversas,
# mas com chaves próprias (avg_reply_time, resolved_conversations_count).
#
# Reusa Reports::SignalSet (fonte única do veredito). Linhas sem conversas no período
# não recebem sinais (evita "vermelho" enganoso para entidades inativas).
module Reports::SummarySignals
  module_function

  def for_row(row)
    row = row.respond_to?(:with_indifferent_access) ? row.with_indifferent_access : row
    return [] if row[:conversations_count].to_i.zero?

    Reports::SignalSet.new(entries: entries_for(row)).build
  end

  def entries_for(row)
    [
      { metric: :first_response, value: row[:avg_first_response_time].to_f },
      { metric: :resolution, value: row[:avg_resolution_time].to_f },
      { metric: :reply, value: row[:avg_reply_time].to_f },
      { metric: :resolution_rate, value: resolution_rate(row) }
    ]
  end

  def resolution_rate(row)
    total = row[:conversations_count].to_i
    return 0 if total.zero?

    ((row[:resolved_conversations_count].to_f / total) * 100).round.clamp(0, 100)
  end
end
