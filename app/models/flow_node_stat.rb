# frozen_string_literal: true

# == Schema Information
#
# Table name: flow_node_stats
#
#  id         :bigint           not null, primary key
#  executions :integer          default(0), not null
#  failures   :integer          default(0), not null
#  node_id    :string           not null
#  period     :string           default("all"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  flow_id    :bigint           not null
#
# Indexes
#
#  index_flow_node_stats_on_account_id             (account_id)
#  index_flow_node_stats_on_flow_id                (flow_id)
#  index_flow_node_stats_on_flow_node_period       (flow_id,node_id,period) UNIQUE
#
# Analytics pré-agregado por nó do Flow (Fase 3.3) — a fonte das pills "142 · 38%" no canvas.
# NÃO é escrito no caminho quente: o Flows::RunnerService já grava um FlowStepLog por nó visitado,
# e o Flows::StatsRollupJob (cron horário) agrega ESSES logs aqui. `period` = 'all' (total vitalício,
# o que a pill mostra) ou 'YYYY-MM-DD' (bucket diário, extensão futura). `executions` conta toda visita
# instrumentada (a base do funil = "quantas vezes o nó foi alcançado"); `failures` é o subconjunto que
# falhou. A porcentagem é DERIVADA na leitura (FlowsController#stats): executions do nó ÷ o maior
# executions do flow no período — o nó de entrada vira 100% e os de baixo mostram a fração que chegou.
class FlowNodeStat < ApplicationRecord
  belongs_to :flow
  belongs_to :account

  # Marcador do total vitalício — a linha que a rollup mantém e a pill lê hoje.
  ALL_TIME = 'all'

  validates :node_id, presence: true
  validates :period, presence: true
  # Uma linha por (nó, período) dentro do flow — o mesmo escopo do índice único e do upsert da rollup.
  validates :node_id, uniqueness: { scope: [:flow_id, :period] }

  scope :for_flow, ->(flow) { where(flow: flow) }
  scope :all_time, -> { where(period: ALL_TIME) }
end
