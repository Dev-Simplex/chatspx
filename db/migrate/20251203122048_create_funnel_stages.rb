class CreateFunnelStages < ActiveRecord::Migration[6.1]
  def change
    create_table :funnel_stages do |t|
      t.string :name, null: false
      t.references :funnel, null: false, foreign_key: true, index: true
      t.integer :position, default: 0
      t.string :color

      t.timestamps
    end
  end
end


