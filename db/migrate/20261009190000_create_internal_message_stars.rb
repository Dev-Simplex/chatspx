class CreateInternalMessageStars < ActiveRecord::Migration[7.1]
  # Aditiva: "Mensagens favoritas" do chat interno, por usuário. Apagar a mensagem ou o usuário
  # leva a estrela junto (cascade), sem travar exclusão.
  def change
    create_table :internal_message_stars do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :internal_message, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :internal_message_stars, [:user_id, :internal_message_id], unique: true, name: 'idx_internal_message_stars_user_message'
  end
end
