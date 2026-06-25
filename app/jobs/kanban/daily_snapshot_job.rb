# frozen_string_literal: true

# Kanban v2 (Fase 6) — capture a daily metric snapshot per funnel (baselines).
# Idempotent: upserts the row for today, so a re-run just refreshes it.
class Kanban::DailySnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Funnel.find_each do |funnel|
      capture(funnel)
    rescue StandardError => e
      Rails.logger.warn("DailySnapshotJob funnel #{funnel.id} failed: #{e.message}")
    end
  end

  private

  def capture(funnel)
    report = Kanban::FunnelReportService.new(funnel: funnel).perform
    metrics = {
      totals: report[:totals],
      stages: report[:stages].map { |s| s.slice(:id, :name, :count, :avg_age_seconds, :overdue) }
    }
    snapshot = funnel.funnel_metric_snapshots.find_or_initialize_by(captured_on: Date.current)
    snapshot.update!(metrics: metrics)
  end
end
