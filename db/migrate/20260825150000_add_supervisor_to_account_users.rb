class AddSupervisorToAccountUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :account_users, :supervisor, :boolean, default: false, null: false

    backfill_supervisor_from_team_supervisors
  end

  def down
    remove_column :account_users, :supervisor
  end

  private

  # "Supervisor" era expresso só por ter linha em team_supervisors. Quem já é
  # ADMINISTRADOR e supervisiona time é o cargo de hoje — recebe a marca. Agente que
  # supervisiona time fica de fora de propósito: aquele é o perfil de supervisão POR
  # TIME, que continua existindo pelas linhas e não deve virar "vê a conta inteira".
  def backfill_supervisor_from_team_supervisors
    supervising = AccountUser.where(role: :administrator)
                             .where(
                               'EXISTS (SELECT 1 FROM team_supervisors ts JOIN teams t ON t.id = ts.team_id ' \
                               'WHERE ts.user_id = account_users.user_id AND t.account_id = account_users.account_id)'
                             )
    # rubocop:disable Rails/SkipsModelValidations
    supervising.update_all(supervisor: true)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
