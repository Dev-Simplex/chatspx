class BackfillMessagesJsonAttributesNull < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  BATCH_SIZE = 5_000

  def up
    backfill_column(:content_attributes)
    backfill_column(:additional_attributes)
  end

  def down
    # Sem rollback intencional: NULL → '{}' é direção de saneamento.
  end

  private

  def backfill_column(column)
    loop do
      affected = execute(<<~SQL.squish).cmd_tuples
        UPDATE messages
        SET #{column} = '{}'
        WHERE id IN (
          SELECT id FROM messages
          WHERE #{column} IS NULL
          LIMIT #{BATCH_SIZE}
          FOR UPDATE SKIP LOCKED
        )
      SQL
      break if affected.to_i.zero?

      sleep 0.05
    end
  end
end
