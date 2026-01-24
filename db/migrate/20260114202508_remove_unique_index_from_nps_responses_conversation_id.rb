class RemoveUniqueIndexFromNpsResponsesConversationId < ActiveRecord::Migration[7.1]
  def change
    remove_index :nps_responses, :conversation_id, if_exists: true
    add_index :nps_responses, :conversation_id
  end
end
