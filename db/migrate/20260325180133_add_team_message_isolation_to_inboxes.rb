class AddTeamMessageIsolationToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :team_message_isolation, :boolean, default: false
  end
end
