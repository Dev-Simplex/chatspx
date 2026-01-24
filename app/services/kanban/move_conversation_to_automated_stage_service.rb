# frozen_string_literal: true

module Kanban
  class MoveConversationToAutomatedStageService
    def initialize(conversation:, status:)
      @conversation = conversation
      @status = status
    end

    def perform
      funnels = []

      if @conversation.team_id.present?
        team_funnel = Funnel.where(team_id: @conversation.team_id, account_id: @conversation.account_id)
                            .find { |f| f.allows_inbox?(@conversation.inbox_id) }
        funnels << team_funnel if team_funnel

        default_funnel = Funnel.where(account_id: @conversation.account_id, team_id: nil)
                               .find { |f| f.allows_inbox?(@conversation.inbox_id) }
        funnels << default_funnel if default_funnel
      else
        default_funnel = Funnel.where(account_id: @conversation.account_id, team_id: nil)
                               .find { |f| f.allows_inbox?(@conversation.inbox_id) }
        funnels << default_funnel if default_funnel
      end

      # Determinar tipo de automação baseado no status
      automation_type = case @status.to_s
                        when 'open', '0'
                          'open'
                        when 'resolved', '1'
                          'resolved'
                        else
                          return nil
                        end

      funnels.compact.uniq.map do |funnel|
        stage = funnel.funnel_stages.with_automation(automation_type).first
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
      Rails.logger.error "Erro ao mover conversa #{@conversation.id} para etapa automatizada: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end
end
