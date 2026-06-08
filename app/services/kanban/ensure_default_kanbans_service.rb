# frozen_string_literal: true

class Kanban::EnsureDefaultKanbansService
  def initialize(account:)
    @account = account
  end

  def perform
    return if @account.blank?

    ensure_default_account_kanban
    ensure_kanbans_for_teams
  end

  private

  def ensure_default_account_kanban
    return if Kanban.exists?(account_id: @account.id, team_id: nil)

    Kanban::CreateDefaultKanbanService.new(account: @account).perform
  rescue StandardError => e
    Rails.logger.error "EnsureDefaultKanbansService: error ensuring default kanban for account #{@account.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def ensure_kanbans_for_teams
    @account.teams.find_each do |team|
      next if Kanban.exists?(team_id: team.id, account_id: @account.id)

      Kanban::CreateKanbanForTeamService.new(team: team).perform
    rescue StandardError => e
      Rails.logger.error "EnsureDefaultKanbansService: error ensuring kanban for team #{team.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end
end
