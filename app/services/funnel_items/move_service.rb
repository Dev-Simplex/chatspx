# frozen_string_literal: true

module FunnelItems
  class MoveService
    attr_reader :conversation, :funnel, :funnel_stage, :moved_by

    def initialize(conversation:, funnel:, funnel_stage:, moved_by:)
      @conversation = conversation
      @funnel = funnel
      @funnel_stage = funnel_stage
      @moved_by = moved_by
    end

    def perform
      funnel_item = FunnelItem.find_or_initialize_by(
        conversation: conversation,
        funnel: funnel
      )

      funnel_item.assign_attributes(
        funnel_stage: funnel_stage,
        moved_by: moved_by,
        moved_at: Time.current
      )

      funnel_item.save!

      update_conversation_status

      funnel_item
    end

    private

    def update_conversation_status
      return unless funnel_stage.automation_type.present?
      return unless conversation.present?

      case funnel_stage.automation_type
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
end
