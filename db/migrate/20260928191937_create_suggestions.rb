class CreateSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :suggestions do |t|
      # account/user nullable de proposito: o link publico (SUG-02) nao tem conta, e apagar uma
      # conta nao pode travar por causa de sugestao — a linha sobrevive com a coluna vazia (T07).
      t.references :account, null: true, foreign_key: { on_delete: :nullify }
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.string :company, null: false
      t.text :content, null: false
      t.integer :source, null: false, default: 0
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :suggestions, :created_at
    add_index :suggestions, :status
  end
end
