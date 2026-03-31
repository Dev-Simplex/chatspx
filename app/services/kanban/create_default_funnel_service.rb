# frozen_string_literal: true

class Kanban::CreateDefaultFunnelService
  def initialize(account:)
    @account = account
  end

  def perform # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return nil if @account.blank?

    existing_funnel = Funnel.find_by(account_id: @account.id, team_id: nil)
    return existing_funnel if existing_funnel.present?

    ActiveRecord::Base.transaction do
      funnel = Funnel.create!(
        name: I18n.t('kanban.stages.general'),
        account_id: @account.id,
        team_id: nil,
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
    Rails.logger.error "Error creating default funnel for account #{@account.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
