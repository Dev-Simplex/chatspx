# frozen_string_literal: true

class CreateDefaultFunnelsForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    # Criar funis padrão para todos os accounts existentes que não têm um
    Account.find_each do |account|
      next if Funnel.exists?(account_id: account.id, team_id: nil)

      Kanban::CreateDefaultFunnelService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error "Erro ao criar funil padrão para account #{account.id}: #{e.message}"
      # Continuar com os próximos accounts mesmo se um falhar
    end
  end

  def down
    # Não há como reverter a criação de funis sem perder dados
    raise ActiveRecord::IrreversibleMigration
  end
end
