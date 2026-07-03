# frozen_string_literal: true

# Kanban v2 (Fase 5) — periodic scan for `time_in_stage` automations: fire a rule
# once a card has been sitting in its stage longer than the configured budget.
# Idempotent per stage-entry: a marker keyed by automation id + moved_at means a
# rule fires at most once per stay (and again only if the card re-enters later).
class Kanban::SlaMonitorJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    FunnelAutomation.active.for_event('time_in_stage').find_each do |automation|
      process_automation(automation)
    rescue StandardError => e
      Rails.logger.warn("SlaMonitorJob automation #{automation.id} failed: #{e.message}")
    end
  end

  private

  def process_automation(automation)
    hours = automation.trigger_hours
    return if hours.blank? || hours <= 0

    items = automation.funnel.funnel_items.where(moved_at: ..hours.hours.ago).includes(:conversation)
    items = items.where(funnel_stage_id: automation.funnel_stage_id) if automation.funnel_stage_id.present?
    items.find_each { |funnel_item| fire_if_due(automation, funnel_item) }
  end

  def fire_if_due(automation, funnel_item)
    conversation = funnel_item.conversation
    return if conversation.blank?

    marker_key = "kanban_auto_#{automation.id}"
    # Microsecond precision so two distinct stays are never confused for one.
    marker = funnel_item.moved_at&.iso8601(6)
    attributes = conversation.custom_attributes || {}
    return if attributes[marker_key] == marker # already fired for this stay

    Kanban::AutomationEngineService.new(
      funnel: automation.funnel,
      conversation: conversation,
      funnel_item: funnel_item,
      moved_by: nil
    ).run(event: 'time_in_stage')

    conversation.update_column(:custom_attributes, attributes.merge(marker_key => marker)) # rubocop:disable Rails/SkipsModelValidations
  end
end
