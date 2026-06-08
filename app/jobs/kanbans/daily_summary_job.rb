# frozen_string_literal: true

# KANBAN-P3-04: enfileira o resumo diário pra cada kanban com a config ativa.
# Modos:
# - perform(kanban_id) → roda um kanban específico (chamada manual).
# - perform_for_all   → roda todos os kanbans onde a hora local bate com a configurada.
class Kanbans::DailySummaryJob < ApplicationJob
  queue_as :default

  def perform(kanban_id = nil)
    if kanban_id
      kanban = Kanban.find_by(id: kanban_id)
      Kanbans::DailySummaryService.call(kanban: kanban) if kanban
      return
    end

    run_for_all
  end

  def self.perform_for_all
    new.send(:run_for_all)
  end

  private

  def run_for_all
    Kanban.find_each do |kanban|
      next unless should_run_now?(kanban)

      begin
        Kanbans::DailySummaryService.call(kanban: kanban)
      rescue StandardError => e
        Rails.logger.tagged('kanban-summary').error("kanban=#{kanban.id} #{e.message}")
      end
    end
  end

  def should_run_now?(kanban)
    cfg = (kanban.settings || {})['daily_summary'] || {}
    return false unless ActiveModel::Type::Boolean.new.cast(cfg['enabled'])

    target_hour = parse_hour(cfg['time_local'])
    return false if target_hour.nil?

    current_hour_in_zone(kanban) == target_hour
  rescue StandardError
    false
  end

  def parse_hour(time_str)
    Integer(time_str.to_s.split(':').first)
  rescue ArgumentError, TypeError
    nil
  end

  def current_hour_in_zone(kanban)
    tz = kanban.account&.timezone.presence || 'UTC'
    Time.now.in_time_zone(tz).hour
  end
end
