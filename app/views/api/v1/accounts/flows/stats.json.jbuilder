# Analytics por nó (Fase 3.3) — a fonte das pills "142 · 38%" no canvas. Cada entrada de `nodes` é
# um FlowNodeStat agregado pelo Flows::StatsRollupJob. `pct` é DERIVADO aqui (não persistido): as
# execuções do nó sobre `total_entries` = o maior executions do flow no período (o nó de entrada,
# alcançado por toda execução, é 100%; os de baixo mostram a fração que chegou). total_entries 0 →
# pct 0 (flow que nunca rodou / sem rollup). O front lê `nodes[node_id]` e desenha "executions · pct%".
# Montamos o hash explicitamente (em vez de um bloco json.set!) pra um flow sem stats sair como `{}`
# e não `null` — um bloco jbuilder vazio serializa nil.
json.period FlowNodeStat::ALL_TIME
json.total_entries @total_entries
json.nodes(@stats.each_with_object({}) do |stat, nodes|
  nodes[stat.node_id] = {
    executions: stat.executions,
    failures: stat.failures,
    pct: @total_entries.zero? ? 0 : ((stat.executions * 100.0) / @total_entries).round
  }
end)
