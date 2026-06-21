class CreateAttachmentBulkDownloads < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :attachment_bulk_downloads do |t|
      t.bigint :account_id, null: false
      t.bigint :requester_user_id
      t.bigint :conversation_id # preenchido apenas no modo "conversa"
      t.integer :status, null: false, default: 0 # pending/processing/completed/failed
      t.jsonb :params, null: false, default: {}   # attachment_ids OU filters (+ select_all)
      t.jsonb :audit_meta, null: false, default: {} # ip, user_agent, origem (gallery|conversation)
      t.integer :total_count, default: 0
      t.integer :processed_count, default: 0
      t.integer :skipped_count, default: 0
      t.bigint :total_bytes, default: 0
      t.bigint :file_size
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :attachment_bulk_downloads, :account_id
    add_index :attachment_bulk_downloads, :requester_user_id
    add_index :attachment_bulk_downloads, :conversation_id
    add_index :attachment_bulk_downloads, :expires_at
    add_index :attachment_bulk_downloads, %i[account_id requester_user_id status],
              name: 'idx_bulk_downloads_on_account_requester_status'
  end
end
