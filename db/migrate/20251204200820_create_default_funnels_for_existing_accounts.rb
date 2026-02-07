# frozen_string_literal: true

class CreateDefaultFunnelsForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      next if Funnel.exists?(account_id: account.id, team_id: nil)

      Kanban::CreateDefaultFunnelService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error "Erro ao criar funil padrão para account #{account.id}: #{e.message}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
