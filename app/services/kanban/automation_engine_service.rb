# frozen_string_literal: true

# Kanban v2 (Fase 5) — declarative automation engine. Given a trigger event for a
# card, it finds the funnel's active rules, checks their conditions and executes
# their actions, reusing Chatwoot's own services so side effects stay intact.
#
# Safety (this is the high-risk phase):
#   * Reentrancy guard — a 'move' action re-triggers the engine; Current's depth
#     counter caps the chain (MAX_DEPTH) so a bad rule can never loop forever.
#   * Best-effort — a failing rule/action is logged and skipped, never raised, so
#     automations can't break a move or a request.
class Kanban::AutomationEngineService
  MAX_DEPTH = 3

  def initialize(funnel:, conversation:, funnel_item:, moved_by: nil)
    @funnel = funnel
    @conversation = conversation
    @funnel_item = funnel_item
    @moved_by = moved_by
  end

  def run(event:)
    return if @funnel.blank? || @conversation.blank?
    return if depth_exceeded?

    automations = matching_automations(event)
    return if automations.empty?

    with_depth do
      automations.each { |automation| run_automation(automation) }
    end
  end

  private

  attr_reader :funnel, :conversation, :funnel_item, :moved_by

  def matching_automations(event)
    funnel.funnel_automations.active.for_event(event).ordered.select do |automation|
      stage_matches?(automation) && conditions_pass?(automation)
    end
  end

  def stage_matches?(automation)
    return true if automation.funnel_stage_id.blank?

    automation.funnel_stage_id == funnel_item&.funnel_stage_id
  end

  def conditions_pass?(automation)
    Array(automation.conditions).all? { |condition| condition_passes?(condition) }
  end

  def condition_passes?(condition)
    actual = field_value(condition['field'])
    value = condition['value']
    case condition['op']
    when 'eq' then actual.to_s == value.to_s
    when 'neq' then actual.to_s != value.to_s
    when 'present' then actual.present?
    when 'blank' then actual.blank?
    when 'includes' then Array(actual).map(&:to_s).include?(value.to_s)
    else false
    end
  end

  def field_value(field)
    case field
    when 'priority' then conversation.priority
    when 'status' then conversation.status
    when 'assignee_id' then conversation.assignee_id
    when 'inbox_id' then conversation.inbox_id
    when 'labels' then conversation.label_list
    end
  end

  def run_automation(automation)
    Array(automation.actions).each { |action| execute_action(action) }
  rescue StandardError => e
    Rails.logger.warn("AutomationEngine rule #{automation.id} failed: #{e.message}")
  end

  def execute_action(action)
    case action['type']
    when 'move' then action_move(action)
    when 'assign' then action_assign(action)
    when 'tag' then action_tag(action)
    when 'webhook' then action_webhook(action)
    when 'enroll_in_sequence' then action_enroll_in_sequence(action)
    end
  rescue StandardError => e
    Rails.logger.warn("AutomationEngine action #{action['type']} failed: #{e.message}")
  end

  def action_move(action)
    stage = funnel.funnel_stages.find_by(id: action['stage_id'])
    return if stage.blank? || stage.id == funnel_item&.funnel_stage_id

    FunnelItems::MoveService.new(
      conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: moved_by
    ).perform
  end

  def action_assign(action)
    Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: action['assignee_id']
    ).perform
  end

  def action_tag(action)
    labels = Array(action['labels']).map(&:to_s).map(&:strip).reject(&:empty?)
    return if labels.empty?

    conversation.add_labels(labels)
  end

  def action_webhook(action)
    url = action['url']
    return if url.blank?

    WebhookJob.perform_later(url, webhook_payload, :account_webhook)
  end

  # Follow-up drip (Módulo A, A3): enrolling a card's conversation into a sequence
  # when it enters a stage / sits too long. EnrollService is idempotent.
  def action_enroll_in_sequence(action)
    sequence = conversation.account.message_sequences.find_by(id: action['sequence_id'])
    return if sequence.blank?

    MessageSequences::EnrollService.new(
      sequence: sequence, conversation: conversation, enrolled_by: moved_by
    ).perform
  end

  def webhook_payload
    {
      event: 'funnel.automation_triggered',
      funnel_id: funnel.id,
      funnel_stage_id: funnel_item&.funnel_stage_id,
      conversation_id: conversation.id,
      conversation_display_id: conversation.display_id
    }
  end

  def depth_exceeded?
    (Current.funnel_automation_depth || 0) >= MAX_DEPTH
  end

  def with_depth
    Current.funnel_automation_depth = (Current.funnel_automation_depth || 0) + 1
    yield
  ensure
    Current.funnel_automation_depth = [(Current.funnel_automation_depth || 1) - 1, 0].max
  end
end
