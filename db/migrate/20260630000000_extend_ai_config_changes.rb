class ExtendAiConfigChanges < ActiveRecord::Migration[7.1]
  # Amplia a trilha de auditoria do receptor de change-sets (Spx::AiConfig::ChangeSetApplier):
  # - error_message: motivo da falha quando apply! grava status:failed (txn separada).
  # - baseline_hash: guard de drift (hash da baseline aprovada pelo control plane).
  # - indices de status e (account_id, created_at) pro histgrico/listagem do Almirante.
  # Additiva e idempotente.
  def change
    add_column :ai_config_changes, :error_message, :text unless column_exists?(:ai_config_changes, :error_message)
    add_column :ai_config_changes, :baseline_hash, :string unless column_exists?(:ai_config_changes, :baseline_hash)

    add_index :ai_config_changes, :status unless index_exists?(:ai_config_changes, :status)
    return if index_exists?(:ai_config_changes, [:account_id, :created_at])

    add_index :ai_config_changes, [:account_id, :created_at]
  end
end
