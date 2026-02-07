# frozen_string_literal: true

module Kanban
  class MoveConversationToTeamFunnelService
    def initialize(conversation:, team: nil)
      @conversation = conversation
      @team = team
    end

    def perform
      funnels = []

      team_id = @team&.id || @conversation.team_id
      if team_id.present?
        team_funnel = Funnel.where(team_id: team_id, account_id: @conversation.account_id)
                            .find { |f| f.allows_inbox?(@conversation.inbox_id) }
        funnels << team_funnel if team_funnel
      end

      default_funnel = Funnel.where(account_id: @conversation.account_id, team_id: nil)
                             .find { |f| f.allows_inbox?(@conversation.inbox_id) }
      funnels << default_funnel if default_funnel

      automation_type = case @conversation.status.to_s
                        when 'open', '0'
                          'open'
                        when 'resolved', '1'
                          'resolved'
                        else
                          nil
                        end

      funnels.compact.uniq.map do |funnel|
        stage = if automation_type.present?
                  funnel.funnel_stages.with_automation(automation_type).first
                else
                  nil
                end

        stage ||= funnel.funnel_stages.ordered.first
        next unless stage.present?

        funnel_item = FunnelItem.find_or_initialize_by(
          conversation_id: @conversation.id,
          funnel_id: funnel.id
        )

        funnel_item.funnel_stage_id = stage.id
        funnel_item.moved_by_id = Current.user&.id
        funnel_item.save!

        funnel_item
      end.compact
    rescue StandardError => e
      Rails.logger.error "Erro ao mover conversa #{@conversation.id} para funil: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end
end
