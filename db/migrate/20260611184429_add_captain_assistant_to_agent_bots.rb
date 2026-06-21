class AddCaptainAssistantToAgentBots < ActiveRecord::Migration[7.1]
  def change
    add_reference :agent_bots, :captain_assistant,
                  null: true, index: false,
                  foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
    add_index :agent_bots, :captain_assistant_id,
              unique: true,
              where: 'captain_assistant_id IS NOT NULL',
              name: 'index_agent_bots_on_captain_assistant_id'
  end
end
