# frozen_string_literal: true

class Kanban::CreateDefaultKanbanService
  def initialize(account:)
    @account = account
  end

  def perform # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return nil if @account.blank?

    existing_kanban = Kanban.find_by(account_id: @account.id, team_id: nil)
    return existing_kanban if existing_kanban.present?

    ActiveRecord::Base.transaction do
      kanban = Kanban.create!(
        name: I18n.t('kanban.stages.general'),
        account_id: @account.id,
        team_id: nil,
        position: 0,
        color: '#94a3b8'
      )

      KanbanStage.create!(
        name: I18n.t('kanban.stages.open'),
        kanban_id: kanban.id,
        position: 0,
        color: '#10b981',
        automation_type: 'open'
      )

      KanbanStage.create!(
        name: I18n.t('kanban.stages.in_progress'),
        kanban_id: kanban.id,
        position: 1,
        color: '#f59e0b',
        automation_type: nil
      )

      KanbanStage.create!(
        name: I18n.t('kanban.stages.resolved'),
        kanban_id: kanban.id,
        position: 2,
        color: '#6b7280',
        automation_type: 'resolved'
      )

      kanban
    end
  rescue StandardError => e
    Rails.logger.error "Error creating default kanban for account #{@account.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
