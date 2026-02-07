class AddInboxIdsToFunnels < ActiveRecord::Migration[7.1]
  def change
    add_column :funnels, :inbox_ids, :jsonb, default: [], null: false
    add_index :funnels, :inbox_ids, using: :gin
  end
end
