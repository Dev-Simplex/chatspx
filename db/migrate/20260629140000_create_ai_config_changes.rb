class CreateAiConfigChanges < ActiveRecord::Migration[7.1]
  # Trilha de auditoria + dado de rollback do receptor de change-sets de
  # comportamento das IAs (Captain). Cada linha = 1 change-set aprovado aplicado
  # nesta VM. snapshot_before guarda o estado anterior por operacao; result
  # guarda ids criados — juntos permitem reverter. Additiva, sem FK destrutiva.
  def change
    create_table :ai_config_changes, if_not_exists: true do |t|
      # id do change-set vindo do control plane (Almirante) — chave de idempotencia.
      t.string :change_set_id, null: false
      t.bigint :account_id, null: false
      # assistant primario do change-set (so pra indexar/buscar; cada op carrega o seu).
      t.bigint :assistant_id
      t.string :author
      t.string :approved_by
      # applied:0 reverted:1 failed:2
      t.integer :status, null: false, default: 0
      # operacoes recebidas, estado anterior (por op) e resultado (ids criados).
      t.jsonb :operations, null: false, default: []
      t.jsonb :snapshot_before, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :applied_at
      t.datetime :reverted_at
      t.timestamps
    end

    add_index :ai_config_changes, :change_set_id, unique: true, if_not_exists: true
    add_index :ai_config_changes, :account_id, if_not_exists: true
  end
end
