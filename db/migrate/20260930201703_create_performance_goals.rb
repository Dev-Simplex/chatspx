class CreatePerformanceGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :performance_goals do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.date :month, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :metric, null: false
      t.decimal :value, precision: 10, scale: 2
      t.timestamps
    end
    add_index :performance_goals, [:account_id, :month, :target_type, :target_id, :metric],
              unique: true, name: 'index_performance_goals_uniqueness'
  end
end
