# frozen_string_literal: true

# Per-node analytics for the Flow engine (Fase 3.3). ONE row = "node X of flow Y ran N times
# (F failures) over `period`". Pré-agregado a partir dos flow_step_logs pelo Flows::StatsRollupJob
# (cron horário): agregar on-the-fly a cada abertura do canvas escanearia uma tabela de logs que só
# cresce — a rollup paga o custo uma vez e a leitura vira um único index hit por flow.
#
# `period` guarda 'all' (o total vitalício — o que a pill "142 · 38%" mostra hoje) OU uma data ISO
# 'YYYY-MM-DD' (buckets diários, extensão futura); por isso é string, não date — um mesmo (flow,node)
# tem no máximo UMA linha por período (índice único). `executions` = todas as visitas instrumentadas
# do nó (success+failed+skipped = "quantas vezes foi alcançado", a base do funil); `failures` = as com
# status failed (sinal de saúde). A % NÃO é persistida: é derivada na leitura (executions / max do
# flow) — assim não precisa recomputar linhas quando o denominador muda. Mirrors o create_flow_step_logs.
class CreateFlowNodeStats < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_node_stats do |t|
      t.references :flow, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string  :node_id, null: false                  # o nó agregado (id definition-local)
      t.integer :executions, null: false, default: 0   # visitas instrumentadas (times reached)
      t.integer :failures, null: false, default: 0     # subconjunto com status failed
      t.string  :period, null: false, default: 'all'   # 'all' (vitalício) OU 'YYYY-MM-DD' (diário)
      t.timestamps
    end

    # Chave da rollup: um upsert idempotente por (flow, nó, período). É também o unique_by do
    # FlowNodeStat.upsert_all — recomputar reescreve a MESMA linha em vez de duplicar.
    add_index :flow_node_stats,
              [:flow_id, :node_id, :period],
              unique: true,
              name: 'index_flow_node_stats_on_flow_node_period'
  end
end
