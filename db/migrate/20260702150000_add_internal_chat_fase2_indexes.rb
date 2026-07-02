# frozen_string_literal: true

# Chat interno — Fase 2 (escala/higiene):
# - dm_key + partial unique index: makes 1:1 DM dedup race-proof at the DB level
#   (FindOrCreateDmService also sets it and rescues RecordNotUnique).
# - GIN indexes on the jsonb columns: foundation for a cross-channel mentions
#   inbox and "who reacted" queries (Fase 3).
# - (internal_channel_id, id): matches the keyset paginator (WHERE id < ? ORDER
#   BY id DESC) so it range-scans instead of using the created_at composite.
#
# Idempotent (safe to re-run). Assumes no duplicate DMs exist — verified on
# staging; the fleet runbook pre-checks accounts before promoting.
class AddInternalChatFase2Indexes < ActiveRecord::Migration[7.1]
  def up
    add_column :internal_channels, :dm_key, :string unless column_exists?(:internal_channels, :dm_key)
    backfill_dm_keys

    add_index :internal_channels, [:account_id, :dm_key], unique: true,
                                                          where: 'channel_type = 0 AND dm_key IS NOT NULL',
                                                          name: 'idx_internal_channels_on_account_and_dm_key', if_not_exists: true

    add_index :internal_messages, :mentioned_user_ids, using: :gin,
                                                       name: 'idx_internal_messages_on_mentioned_user_ids', if_not_exists: true
    add_index :internal_messages, :reactions, using: :gin,
                                              name: 'idx_internal_messages_on_reactions', if_not_exists: true
    add_index :internal_messages, [:internal_channel_id, :id],
              name: 'idx_internal_messages_on_channel_and_id', if_not_exists: true
  end

  def down
    remove_index :internal_channels, name: 'idx_internal_channels_on_account_and_dm_key', if_exists: true
    remove_column :internal_channels, :dm_key, if_exists: true
    remove_index :internal_messages, name: 'idx_internal_messages_on_mentioned_user_ids', if_exists: true
    remove_index :internal_messages, name: 'idx_internal_messages_on_reactions', if_exists: true
    remove_index :internal_messages, name: 'idx_internal_messages_on_channel_and_id', if_exists: true
  end

  private

  # Backfill dm_key = sorted member ids for existing direct channels.
  def backfill_dm_keys
    execute(<<~SQL.squish)
      UPDATE internal_channels ic SET dm_key = sub.key
      FROM (
        SELECT icm.internal_channel_id AS cid,
               string_agg(icm.user_id::text, '-' ORDER BY icm.user_id) AS key
        FROM internal_channel_members icm
        GROUP BY icm.internal_channel_id
      ) sub
      WHERE ic.id = sub.cid AND ic.channel_type = 0 AND ic.dm_key IS NULL
    SQL
  end
end
