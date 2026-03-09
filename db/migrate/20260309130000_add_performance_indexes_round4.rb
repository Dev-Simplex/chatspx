class AddPerformanceIndexesRound4 < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # Covers DISTINCT ON (conversation_id) queries in ListPreloader
    # that filter by team_id and order by created_at DESC, id DESC
    add_index :messages,
              %i[conversation_id team_id created_at id],
              order: { created_at: :desc, id: :desc },
              name: 'idx_messages_conv_team_created_desc',
              algorithm: :concurrently,
              if_not_exists: true

    # Covers UPDATE messages SET team_id WHERE ... bulk assignment queries
    add_index :messages,
              :team_id,
              name: 'idx_messages_team_id',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
