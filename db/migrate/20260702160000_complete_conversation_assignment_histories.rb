class CompleteConversationAssignmentHistories < ActiveRecord::Migration[7.1]
  # A tabela `conversation_assignment_histories` já existe no schema.rb (dormante: sem model,
  # sem writer). Esta migration a COMPLETA com o ator da atribuição (`assigned_by_id`) e a
  # origem (`source`), pra suportar o Relatório de Atribuições por Agente.
  #
  # Additive e defensiva (create-if-missing + add-column-if-missing + add-index-if-missing) →
  # segura pro botão Deploy da frota (roda db:migrate). Ver docs/plano-download-massa-midias.md §5.2.
  def change
    # Fallback pra DBs antigos que nunca receberam a tabela (o schema.rb tem, mas foi adicionada
    # direto — não há create_table). Na frota atual a tabela existe (a FK migration 20260330120000
    # já roda sobre ela), então este bloco vira no-op.
    unless table_exists?(:conversation_assignment_histories)
      create_table :conversation_assignment_histories do |t|
        t.bigint   :conversation_id, null: false
        t.bigint   :account_id,      null: false
        t.bigint   :assignee_id
        t.bigint   :team_id
        t.datetime :assigned_at,     null: false
        t.datetime :unassigned_at
        t.timestamps
      end
    end

    add_column :conversation_assignment_histories, :assigned_by_id, :bigint unless column_exists?(:conversation_assignment_histories, :assigned_by_id)

    unless column_exists?(:conversation_assignment_histories, :source)
      add_column :conversation_assignment_histories, :source, :integer, default: 6, null: false
    end

    unless index_exists?(:conversation_assignment_histories, [:account_id, :assigned_at])
      add_index :conversation_assignment_histories, [:account_id, :assigned_at], name: 'idx_cah_account_assigned_at'
    end

    add_index :conversation_assignment_histories, :assignee_id unless index_exists?(:conversation_assignment_histories, :assignee_id)

    return if index_exists?(:conversation_assignment_histories, :assigned_by_id)

    add_index :conversation_assignment_histories, :assigned_by_id
  end
end
