class AddAgentConversationIsolationToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :agent_conversation_isolation, :boolean, default: false, null: false
  end
end
