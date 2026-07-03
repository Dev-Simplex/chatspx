# frozen_string_literal: true

# Kanban v2 (Fase 6) — live operational stats for a funnel's in-board dashboard.
# A handful of grouped queries over funnel_items ⋈ conversations, leaning on the
# existing indexes (funnel_id, funnel_stage_id, moved_at). No per-card loading.
class Kanban::FunnelReportService
  WORKLOAD_LIMIT = 10

  def initialize(funnel:)
    @funnel = funnel
  end

  def perform
    {
      generated_at: Time.current,
      totals: totals,
      stages: stage_stats,
      workload: workload
    }
  end

  private

  attr_reader :funnel

  # Base scope: every card of the funnel joined to its conversation.
  def items
    @items ||= funnel.funnel_items.joins(:conversation)
  end

  def totals
    {
      cards: items.count,
      by_status: status_breakdown,
      unassigned: items.where(conversations: { assignee_id: nil }).count,
      created_today: funnel.funnel_items.where(created_at: Time.current.all_day).count,
      resolved_today: resolved_today,
      overdue: stage_stats.sum { |s| s[:overdue] }
    }
  end

  def status_breakdown
    names = Conversation.statuses.invert
    items.group('conversations.status').count.transform_keys { |code| names[code] || code.to_s }
  end

  def resolved_today
    items.where(conversations: { status: Conversation.statuses[:resolved] })
         .where(conversations: { updated_at: Time.current.all_day })
         .count
  end

  def stage_stats
    @stage_stats ||= build_stage_stats
  end

  def build_stage_stats
    counts = items.group(:funnel_stage_id).count
    ages = items.group(:funnel_stage_id).average(Arel.sql('EXTRACT(EPOCH FROM (now() - funnel_items.moved_at))'))
    unassigned = items.where(conversations: { assignee_id: nil }).group(:funnel_stage_id).count

    funnel.funnel_stages.ordered.map { |stage| stage_row(stage, counts, ages, unassigned) }
  end

  def stage_row(stage, counts, ages, unassigned)
    {
      id: stage.id,
      name: stage.name,
      color: stage.color,
      count: counts[stage.id] || 0,
      avg_age_seconds: ages[stage.id]&.to_f&.round,
      unassigned: unassigned[stage.id] || 0,
      sla_hours: stage.sla_hours.presence&.to_i,
      overdue: overdue_count(stage)
    }
  end

  def overdue_count(stage)
    hours = stage.sla_hours.to_i
    return 0 if hours <= 0

    items.where(funnel_stage_id: stage.id).where(funnel_items: { moved_at: ..hours.hours.ago }).count
  end

  def workload
    rows = items.where.not(conversations: { assignee_id: nil })
                .group('conversations.assignee_id').count
    users = User.where(id: rows.keys).index_by(&:id)
    rows.map { |user_id, count| { assignee_id: user_id, name: user_name(users[user_id]), count: count } }
        .sort_by { |row| -row[:count] }
        .first(WORKLOAD_LIMIT)
  end

  def user_name(user)
    return nil if user.blank?

    user.available_name.presence || user.name
  end
end
