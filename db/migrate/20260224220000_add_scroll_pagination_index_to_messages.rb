# frozen_string_literal: true

class AddScrollPaginationIndexToMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :messages,
              [:conversation_id, :inbox_id, :team_id, :id],
              order: { id: :desc },
              name: 'idx_messages_conv_inbox_team_id_desc',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
