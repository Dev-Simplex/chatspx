# frozen_string_literal: true

class AddConversationsListKeysetIndex < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :conversations,
              %i[account_id status assignee_id last_activity_at id],
              order: { last_activity_at: :desc, id: :desc },
              name: 'idx_conv_list_keyset',
              algorithm: :concurrently
  end
end
