# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # nps_responses: queries filtradas por account + status + data (métricas e job de expiração)
    add_index :nps_responses,
              %i[account_id status sent_at],
              name: 'idx_nps_responses_account_status_sent_at',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :nps_responses,
              %i[account_id status answered_at],
              name: 'idx_nps_responses_account_status_answered_at',
              algorithm: :concurrently,
              if_not_exists: true

    # conversations: queries filtradas por time + status (live reports e dashboard)
    add_index :conversations,
              %i[team_id status],
              name: 'idx_conversations_team_id_status',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
