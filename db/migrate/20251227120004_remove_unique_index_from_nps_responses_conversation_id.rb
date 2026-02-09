class RemoveUniqueIndexFromNpsResponsesConversationId < ActiveRecord::Migration[7.1]
  def change
    return unless table_exists?(:nps_responses)

    remove_index :nps_responses, :conversation_id, if_exists: true
    add_index :nps_responses, :conversation_id unless index_exists?(:nps_responses, :conversation_id)
  end
end
