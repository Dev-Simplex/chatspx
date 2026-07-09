# frozen_string_literal: true

# Rollup do analytics por nó (Fase 3.3): agrega os flow_step_logs num FlowNodeStat por (flow, nó),
# alimentando as pills "142 · 38%" do canvas. Roda de hora em hora (config/schedule.yml) para a
# leitura no canvas ser um único index hit em vez de um GROUP BY numa tabela de logs que só cresce.
#
# IDEMPOTENTE POR CONSTRUÇÃO: recomputa o total a partir de TODOS os logs e faz upsert com SET (não
# incremento) — rodar duas vezes seguidas deixa as MESMAS linhas. `executions` conta toda visita
# instrumentada (success+failed+skipped = "quantas vezes o nó foi alcançado"); `failures` é o
# subconjunto com status failed. Só o período 'all' (total vitalício) é materializado aqui; a coluna
# `period` já comporta buckets diários numa extensão futura sem migração.
class Flows::StatsRollupJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    rows = aggregate_rows
    return if rows.empty?

    persist_rows(rows)
  end

  private

  # UM GROUP BY por (flow, conta, nó): total de visitas e quantas falharam. Ignora logs sem node_id
  # (defensivo — o walker sempre passa node['id'], mas a coluna é nullable). O FILTER agrega os dois
  # contadores numa passada só.
  def aggregate_rows
    failed = FlowStepLog.statuses.fetch('failed')
    now = Time.current

    FlowStepLog
      .where.not(node_id: nil)
      .group(:flow_id, :account_id, :node_id)
      .pluck(
        :flow_id, :account_id, :node_id,
        Arel.sql('COUNT(*)'),
        Arel.sql("COUNT(*) FILTER (WHERE status = #{failed})")
      )
      .map do |flow_id, account_id, node_id, executions, failures|
        {
          flow_id: flow_id, account_id: account_id, node_id: node_id,
          period: FlowNodeStat::ALL_TIME, executions: executions, failures: failures,
          created_at: now, updated_at: now
        }
      end
  end

  # Upsert idempotente: o índice único (flow_id, node_id, period) casa a linha existente e o SET
  # sobrescreve com o total recomputado. created_at só entra na inserção (o EXCLUDED não o toca).
  def persist_rows(rows)
    # rubocop:disable Rails/SkipsModelValidations
    FlowNodeStat.upsert_all(
      rows,
      unique_by: %i[flow_id node_id period],
      on_duplicate: Arel.sql('executions = EXCLUDED.executions, failures = EXCLUDED.failures, updated_at = EXCLUDED.updated_at')
    )
    # rubocop:enable Rails/SkipsModelValidations
  end
end
