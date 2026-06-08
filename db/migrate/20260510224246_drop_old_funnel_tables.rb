class DropOldFunnelTables < ActiveRecord::Migration[7.0]
  def up
    drop_table :funnel_items, force: :cascade
    drop_table :funnel_stages, force: :cascade
    drop_table :funnels, force: :cascade
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'DROP+RECREATE: irreversivel. Restaurar de backup.'
  end
end
