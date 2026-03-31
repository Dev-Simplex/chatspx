# frozen_string_literal: true

class Kanban::MoveConversationToTeamFunnelService
  pattr_initialize [:conversation!, { team: nil }]

  def perform # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    team_id = team&.id || conversation.team_id

    funnels = Kanban::FunnelLookupService.new(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, team_id: team_id
    ).perform

    automation_type = resolve_automation_type

    funnels.filter_map do |funnel|
      stage = (funnel.funnel_stages.with_automation(automation_type).first if automation_type.present?)
      stage ||= funnel.funnel_stages.ordered.first
      next if stage.blank?

      funnel_item = FunnelItem.find_or_initialize_by(conversation_id: conversation.id, funnel_id: funnel.id)
      funnel_item.funnel_stage_id = stage.id
      funnel_item.moved_by_id = Current.user&.id
      funnel_item.save!
      funnel_item
    end
  rescue StandardError => e
    Rails.logger.error "Error moving conversation #{conversation.id} to funnel: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end

  private

  def resolve_automation_type
    case conversation.status.to_s
    when 'open', '0' then 'open'
    when 'resolved', '1' then 'resolved'
    end
  end
end
