class CreateFunnelItems < ActiveRecord::Migration[6.1]
  def change
    create_table :funnel_items do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :funnel, null: false, foreign_key: true, index: true
      t.references :funnel_stage, null: false, foreign_key: true, index: true
      t.datetime :moved_at
      t.references :moved_by, null: true, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end

    add_index :funnel_items, [:conversation_id, :funnel_id], unique: true, name: 'index_funnel_items_unique'
  end
end
