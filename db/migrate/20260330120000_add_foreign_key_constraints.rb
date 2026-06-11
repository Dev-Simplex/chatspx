# Adiciona FK constraints nas tabelas core (versao SAFE / nao-destrutiva).
# Orfao em coluna nullable -> NULA o campo (preserva a linha).
# Orfao NOT NULL em conversations/messages -> ABORTA listando os IDs (NAO deleta).
# Orfao NOT NULL em tabela filha/junction -> remove (garbage de pai inexistente).
# Padrao nao-bloqueante (disable_ddl_transaction + FK validate:false): sem downtime.

class AddForeignKeyConstraints < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Adds foreign key constraints to core tables that were created before FK conventions were adopted.
  # Non-blocking pattern: sanitize orphans (NULLIFY se anulavel / DELETE se irreparavel) -> add unvalidated FK -> validate separately.
  FOREIGN_KEYS = [
    # Filhos de conversations PRIMEIRO (cascade) — mesmo do original
    { from: :conversation_assignment_histories, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :applied_slas, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :sla_events, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :funnel_items, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :scheduled_messages, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :nps_responses, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :csat_survey_responses, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :reporting_events, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: true },
    { from: :conversation_participants, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :mentions, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },
    { from: :messages, to: :conversations, column: :conversation_id, on_delete: :cascade, nullable: false },

    # core
    { from: :conversations, to: :accounts,  column: :account_id,  on_delete: :cascade,  nullable: false },
    { from: :conversations, to: :inboxes,   column: :inbox_id,    on_delete: :cascade,  nullable: false },
    { from: :conversations, to: :contacts,  column: :contact_id,  on_delete: :restrict, nullable: true },
    { from: :conversations, to: :users,     column: :assignee_id, on_delete: :nullify,  nullable: true },
    { from: :conversations, to: :teams,     column: :team_id,     on_delete: :nullify,  nullable: true },
    { from: :messages,      to: :accounts,  column: :account_id,  on_delete: :cascade,  nullable: false },
    { from: :messages,      to: :inboxes,   column: :inbox_id,    on_delete: :cascade,  nullable: false },

    { from: :notifications, to: :accounts, column: :account_id, on_delete: :cascade, nullable: false },
    { from: :notifications, to: :users,    column: :user_id,    on_delete: :cascade, nullable: false },
    { from: :contact_inboxes, to: :contacts, column: :contact_id, on_delete: :cascade, nullable: true },
    { from: :contact_inboxes, to: :inboxes,  column: :inbox_id,   on_delete: :cascade, nullable: true },
    { from: :conversation_participants, to: :accounts, column: :account_id, on_delete: :cascade, nullable: false }
  ].freeze

  # Tabelas "preciosas": NUNCA apagar uma linha delas por orfao NOT NULL.
  # Se houver orfao NOT NULL aqui, ABORTA a migration listando os IDs (decisao humana).
  PRECIOUS_TABLES = %i[conversations messages].freeze

  def up
    # tabelas grandes (messages, reporting_events) demoram no validate/cleanup e estouram
    # o statement_timeout do banco. Afrouxa SO para esta sessao de migration (online, sem lock exclusivo).
    connection.execute("SET statement_timeout = '60min'")
    FOREIGN_KEYS.each { |fk| add_fk(fk) }
  end

  def down
    FOREIGN_KEYS.reverse_each { |fk| remove_fk(fk) }
  end

  private

  def add_fk(fk)
    from_table = fk[:from]
    to_table   = fk[:to]
    column     = fk[:column]
    on_delete  = fk[:on_delete]

    # Pula a FK se a tabela (origem OU destino) nao existir neste schema
    # (ex: conversation_assignment_histories ausente em algumas VMs) — evita PG::UndefinedTable
    return unless table_exists?(from_table) && table_exists?(to_table)

    # Re-add com o on_delete correto se ja existir
    remove_foreign_key from_table, to_table, column: column if foreign_key_exists?(from_table, to_table, column: column)

    # Step 1: sanitizar orfaos SEM destruir dado de negocio.
    # Decide pela NULABILIDADE REAL da coluna (nao pelo flag :nullable da lista).
    if column_accepts_null?(from_table, column)
      # coluna aceita NULL -> NULA a referencia orfa (preserva a linha; protege conversas/contact_inboxes)
      safety_execute(<<~SQL.squish)
        UPDATE #{from_table} SET #{column} = NULL
        WHERE #{column} IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
      SQL
    elsif PRECIOUS_TABLES.include?(from_table)
      # coluna NOT NULL numa tabela PRECIOSA (conversations/messages): NAO deletar.
      # Aborta listando os IDs orfaos -> humano trata caso-a-caso. NENHUMA linha apagada.
      orphan_ids = connection.select_values(<<~SQL.squish)
        SELECT id FROM #{from_table}
        WHERE NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
        ORDER BY id LIMIT 100
      SQL
      if orphan_ids.any?
        total = connection.select_value(<<~SQL.squish)
          SELECT COUNT(*) FROM #{from_table}
          WHERE NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
        SQL
        raise "ABORT FK #{from_table}.#{column}->#{to_table}: #{total} orfao(s) NOT NULL em tabela preciosa. " \
              "Tratar manualmente ANTES de aplicar (ex IDs: #{orphan_ids.first(50).join(',')}). Nenhuma linha foi apagada."
      end
    else
      # coluna NOT NULL numa tabela filha/junction -> orfao e garbage irreparavel -> remover
      safety_execute(<<~SQL.squish)
        DELETE FROM #{from_table}
        WHERE NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
      SQL
    end

    # Step 2: FK sem validar (instantaneo, sem lock)
    add_foreign_key from_table, to_table, column: column, on_delete: on_delete, validate: false

    # Step 3: validar (scaneia, sem lock exclusivo)
    validate_foreign_key from_table, to_table, column: column
  end

  def remove_fk(fk)
    return unless foreign_key_exists?(fk[:from], fk[:to], column: fk[:column])

    remove_foreign_key fk[:from], fk[:to], column: fk[:column]
  end

  def column_accepts_null?(table, column)
    col = connection.columns(table.to_s).find { |c| c.name == column.to_s }
    col ? col.null : false
  end

  def safety_execute(sql)
    say_with_time(sql.truncate(120)) { execute(sql) }
  end
end
