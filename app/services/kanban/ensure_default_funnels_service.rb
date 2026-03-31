# frozen_string_literal: true

class Kanban::EnsureDefaultFunnelsService
  def initialize(account:)
    @account = account
  end

  def perform
    return if @account.blank?

    ensure_default_account_funnel
    ensure_funnels_for_teams
  end

  private

  def ensure_default_account_funnel
    return if Funnel.exists?(account_id: @account.id, team_id: nil)

    CreateDefaultFunnelService.new(account: @account).perform
  rescue StandardError => e
    Rails.logger.error "EnsureDefaultFunnelsService: error ensuring default funnel for account #{@account.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def ensure_funnels_for_teams
    @account.teams.find_each do |team|
      next if Funnel.exists?(team_id: team.id, account_id: @account.id)

      CreateFunnelForTeamService.new(team: team).perform
    rescue StandardError => e
      Rails.logger.error "EnsureDefaultFunnelsService: error ensuring funnel for team #{team.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end
end
