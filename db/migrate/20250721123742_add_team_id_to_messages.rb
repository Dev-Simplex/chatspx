class AddTeamIdToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :team_id, :integer
  end
end
