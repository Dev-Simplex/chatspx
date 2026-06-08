# frozen_string_literal: true

class KanbanItems::MoveService
  attr_reader :conversation, :kanban, :kanban_stage, :moved_by

  def initialize(conversation:, kanban:, kanban_stage:, moved_by:)
    @conversation = conversation
    @kanban = kanban
    @kanban_stage = kanban_stage
    @moved_by = moved_by
  end

  def perform
    kanban_item = KanbanItem.find_or_initialize_by(
      conversation: conversation,
      kanban: kanban
    )

    previous_stage_id = kanban_item.kanban_stage_id

    kanban_item.assign_attributes(
      kanban_stage: kanban_stage,
      moved_by: moved_by,
      last_stage_change_at: Time.current
    )

    kanban_item.save!

    update_conversation_status
    fire_automations(kanban_item, previous_stage_id)

    kanban_item
  end

  private

  def fire_automations(item, previous_stage_id)
    return if previous_stage_id == item.kanban_stage_id

    if previous_stage_id.present?
      KanbanAutomations::DispatcherService.fire(
        trigger: 'item_left_stage', item: item, previous_stage_id: previous_stage_id
      )
    end
    KanbanAutomations::DispatcherService.fire(
      trigger: 'item_entered_stage', item: item
    )
  rescue StandardError => e
    Rails.logger.tagged('kanban-automations').warn("fire failed: #{e.message}")
  end

  def update_conversation_status
    return if kanban_stage.automation_type.blank?
    return if conversation.blank?

    case kanban_stage.automation_type
    when 'resolved'
      resolve_conversation_from_automation! unless conversation.resolved?
    when 'open'
      conversation.update!(status: :open) unless conversation.open?
    end
  end

  def resolve_conversation_from_automation!
    conversation.skip_team_required_for_resolution_validation = true
    conversation.update!(status: :resolved)
  ensure
    conversation.skip_team_required_for_resolution_validation = false
  end
end
