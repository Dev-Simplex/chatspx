class AddPerformanceIndexesRound3 < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :conversations,
              %i[account_id status first_reply_created_at waiting_since],
              name: 'idx_conv_unattended_counts',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :conversations,
              %i[account_id status last_activity_at waiting_since],
              name: 'idx_conv_resolvable_not_waiting',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :nps_responses,
              %i[account_id status created_at],
              name: 'idx_nps_account_status_created',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
