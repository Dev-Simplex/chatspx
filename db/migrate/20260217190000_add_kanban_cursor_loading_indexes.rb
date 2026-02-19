# frozen_string_literal: true

class AddKanbanCursorLoadingIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :funnel_items,
              [:funnel_id, :funnel_stage_id, :conversation_id],
              name: 'idx_funnel_items_funnel_stage_conversation',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :conversations,
              [:account_id, :status, :last_activity_at, :id],
              order: { last_activity_at: :desc, id: :desc },
              name: 'idx_conv_kanban_keyset',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
