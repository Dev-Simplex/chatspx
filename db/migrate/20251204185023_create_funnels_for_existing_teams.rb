# frozen_string_literal: true

class CreateFunnelsForExistingTeams < ActiveRecord::Migration[7.1]
  def up
    Team.find_each do |team|
      next if Funnel.exists?(team_id: team.id, account_id: team.account_id)

      Kanban::CreateFunnelForTeamService.new(team: team).perform
    rescue StandardError => e
      Rails.logger.error "Erro ao criar funil para time #{team.id}: #{e.message}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
