# Indice composto em attachments(message_id, file_type) para queries da
# galeria/atendimento que sempre filtram por mensagem + tipo de arquivo.
# Auditoria PostgreSQL identificou ~17.3 bi tuplas lidas em 7 dias por queries
# que hoje usam apenas o indice (message_id) e filtram file_type em memoria.
# CONCURRENTLY para nao bloquear escrita (tabela ~323k rows: ~30-60 s em SSD).
# Ref: docs/stories/sprint-2026-05-13/P1.6-pg-autovacuum-indices-mortos.md (AC3)
class AddAttachmentsMessageIdFileTypeIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute 'SET statement_timeout = 0'

    add_index :attachments, %i[message_id file_type],
              name: 'idx_attachments_message_id_file_type',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    execute 'SET statement_timeout = 0'

    remove_index :attachments, name: 'idx_attachments_message_id_file_type',
                               algorithm: :concurrently, if_exists: true
  end
end
