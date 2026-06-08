# frozen_string_literal: true

class Kanban::MoveConversationToAutomatedStageService
  pattr_initialize [:conversation!, :status!]

  def perform # rubocop:disable Metrics/AbcSize
    automation_type = resolve_automation_type
    return if automation_type.nil?

    kanbans = Kanban::KanbanLookupService.new(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, team_id: conversation.team_id
    ).perform

    kanbans.filter_map do |kanban|
      stage = kanban.kanban_stages.with_automation(automation_type).first
      next if stage.blank?

      kanban_item = KanbanItem.find_or_initialize_by(conversation_id: conversation.id, kanban_id: kanban.id)
      kanban_item.kanban_stage_id = stage.id
      kanban_item.moved_by_id = Current.user&.id
      kanban_item.save!
      kanban_item
    end
  rescue StandardError => e
    Rails.logger.error "Error moving conversation #{conversation.id} to automated stage: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end

  private

  def resolve_automation_type
    case status.to_s
    when 'open', '0' then 'open'
    when 'resolved', '1' then 'resolved'
    end
  end
end
