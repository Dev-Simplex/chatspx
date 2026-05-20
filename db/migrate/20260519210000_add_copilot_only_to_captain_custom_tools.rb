class AddCopilotOnlyToCaptainCustomTools < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_custom_tools, :copilot_only, :boolean, default: false, null: false
  end
end
