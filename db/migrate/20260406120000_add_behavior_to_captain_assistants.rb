class AddBehaviorToCaptainAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :captain_assistants, :behavior, :jsonb, null: false, default: {}
  end
end
