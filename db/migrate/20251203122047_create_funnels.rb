class CreateFunnels < ActiveRecord::Migration[6.1]
  def change
    create_table :funnels do |t|
      t.string :name, null: false
      t.references :account, null: false, foreign_key: true, index: true
      t.integer :position, default: 0
      t.string :color

      t.timestamps
    end
  end
end


