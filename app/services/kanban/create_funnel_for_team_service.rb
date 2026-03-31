# frozen_string_literal: true

class Kanban::CreateFunnelForTeamService
  def initialize(team:)
    @team = team
  end

  def perform # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return nil if @team.blank?

    existing_funnel = Funnel.find_by(team_id: @team.id, account_id: @team.account_id)
    return existing_funnel if existing_funnel.present?

    ActiveRecord::Base.transaction do
      funnel = Funnel.create!(
        name: @team.name,
        account_id: @team.account_id,
        team_id: @team.id,
        position: 0,
        color: '#94a3b8'
      )

      FunnelStage.create!(
        name: I18n.t('kanban.stages.open'),
        funnel_id: funnel.id,
        position: 0,
        color: '#10b981',
        automation_type: 'open'
      )

      FunnelStage.create!(
        name: I18n.t('kanban.stages.in_progress'),
        funnel_id: funnel.id,
        position: 1,
        color: '#f59e0b',
        automation_type: nil
      )

      FunnelStage.create!(
        name: I18n.t('kanban.stages.resolved'),
        funnel_id: funnel.id,
        position: 2,
        color: '#6b7280',
        automation_type: 'resolved'
      )

      funnel
    end
  rescue StandardError => e
    Rails.logger.error "Error creating funnel for team #{@team.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
