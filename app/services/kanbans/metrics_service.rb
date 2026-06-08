# frozen_string_literal: true

# KANBAN-P2-05: calcula métricas do board (header).
# - total: contagem de cards ativos (nao won/loss stages)
# - pipeline_value_cents: soma de metadata.value_cents dos cards ativos
# - average_aging_days: media de aging_days nos cards ativos
# - win_rate: won / (won + loss) nos ultimos 30 dias
#
# Cache via Rails.cache (Redis em prod) com TTL 60s. Chave por kanban_id.
class Kanbans::MetricsService
  CACHE_TTL = 60.seconds
  WIN_RATE_WINDOW_DAYS = 30

  attr_reader :kanban

  def initialize(kanban:)
    @kanban = kanban
  end

  def perform
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      compute
    end
  end

  def self.call(kanban:)
    new(kanban: kanban).perform
  end

  def self.invalidate(kanban_id)
    Rails.cache.delete("kanban:metrics:#{kanban_id}")
  end

  private

  def cache_key
    "kanban:metrics:#{kanban.id}"
  end

  def compute
    active_items = kanban.kanban_items
                         .joins(:kanban_stage)
                         .where(kanban_stages: { won_loss_type: nil })

    {
      total: kanban.kanban_items.count,
      active_total: active_items.count,
      pipeline_value_cents: pipeline_value(active_items),
      # P3-06: pipeline ponderado por probability da stage.
      weighted_pipeline_value_cents: weighted_pipeline_value(active_items),
      average_aging_days: average_aging(active_items),
      win_rate: win_rate,
      generated_at: Time.current
    }
  end

  def pipeline_value(scope)
    scope.sum("COALESCE((metadata->>'value_cents')::bigint, 0)").to_i
  end

  def weighted_pipeline_value(scope)
    scope.sum(
      'COALESCE((kanban_items.metadata->>\'value_cents\')::bigint, 0) * COALESCE(kanban_stages.probability, 0) / 100.0'
    ).to_i
  end

  def average_aging(scope)
    avg = scope.average(:aging_days)
    return 0.0 if avg.blank?

    avg.to_f.round(1)
  end

  def win_rate
    since = WIN_RATE_WINDOW_DAYS.days.ago
    grouped = kanban.kanban_items
                    .joins(:kanban_stage)
                    .where.not(kanban_stages: { won_loss_type: nil })
                    .where('kanban_items.updated_at >= ?', since)
                    .group('kanban_stages.won_loss_type')
                    .count
    won = grouped['won'] || 0
    loss = grouped['loss'] || 0
    total = won + loss
    return nil if total.zero?

    ((won.to_f / total) * 100).round(1)
  end
end
