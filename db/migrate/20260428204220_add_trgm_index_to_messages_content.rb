class AddTrgmIndexToMessagesContent < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension('pg_trgm') unless extension_enabled?('pg_trgm')

    return if index_exists?(:messages, :content, name: 'index_messages_on_content_trgm')

    # CREATE INDEX CONCURRENTLY pode exceder statement_timeout em tabelas grandes
    execute 'SET statement_timeout = 0'

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_messages_on_content_trgm
        ON messages USING gin (content gin_trgm_ops)
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_messages_on_content_trgm
    SQL
  end
end
