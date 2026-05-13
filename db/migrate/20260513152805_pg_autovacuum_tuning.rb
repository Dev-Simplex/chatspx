# Per-table autovacuum tuning identificado na auditoria PostgreSQL (2026-05-13).
# Default autovacuum_vacuum_scale_factor=0.20 deixa muito bloat acumular em
# tabelas quentes (messages, conversations, attachments, active_storage_blobs).
# Baixar para 0.05 (analyze para 0.02 onde aplicavel) faz autovacuum rodar mais
# cedo e mais vezes, reduzindo bloat e melhorando HOT update %.
# Ref: docs/stories/sprint-2026-05-13/P1.6-pg-autovacuum-indices-mortos.md (AC1)
class PgAutovacuumTuning < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL.squish)
      ALTER TABLE messages SET (
        autovacuum_vacuum_scale_factor = 0.05,
        autovacuum_analyze_scale_factor = 0.02
      )
    SQL

    execute(<<~SQL.squish)
      ALTER TABLE conversations SET (
        autovacuum_vacuum_scale_factor = 0.05,
        autovacuum_analyze_scale_factor = 0.02
      )
    SQL

    execute(<<~SQL.squish)
      ALTER TABLE attachments SET (autovacuum_vacuum_scale_factor = 0.05)
    SQL

    execute(<<~SQL.squish)
      ALTER TABLE active_storage_blobs SET (autovacuum_vacuum_scale_factor = 0.05)
    SQL
  end

  def down
    execute('ALTER TABLE messages RESET (autovacuum_vacuum_scale_factor, autovacuum_analyze_scale_factor)')
    execute('ALTER TABLE conversations RESET (autovacuum_vacuum_scale_factor, autovacuum_analyze_scale_factor)')
    execute('ALTER TABLE attachments RESET (autovacuum_vacuum_scale_factor)')
    execute('ALTER TABLE active_storage_blobs RESET (autovacuum_vacuum_scale_factor)')
  end
end
