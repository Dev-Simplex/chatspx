# frozen_string_literal: true

class CreateFunnelsForExistingTeams < ActiveRecord::Migration[7.1]
  def up
    # Criar funis para todos os times existentes
    Team.find_each do |team|
      next if Funnel.exists?(team_id: team.id, account_id: team.account_id)

      Kanban::CreateFunnelForTeamService.new(team: team).perform
    rescue StandardError => e
      Rails.logger.error "Erro ao criar funil para time #{team.id}: #{e.message}"
      # Continuar com os próximos times mesmo se um falhar
    end
  end

  def down
    # Não há como reverter a criação de funis sem perder dados
    raise ActiveRecord::IrreversibleMigration
  end
end
