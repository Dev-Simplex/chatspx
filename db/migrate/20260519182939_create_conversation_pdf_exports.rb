class CreateConversationPdfExports < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :conversation_pdf_exports do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :requester_user, null: true, foreign_key: { to_table: :users, on_delete: :nullify }

      t.integer :status, null: false, default: 0
      t.jsonb :filters, null: false, default: {}
      t.jsonb :audit_meta, null: false, default: {}

      t.string :sha256, limit: 64
      t.bigint :file_size
      t.integer :bates_count
      t.binary :timestamp_token

      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.text :error_message

      t.timestamps
    end

    add_index :conversation_pdf_exports, %i[conversation_id created_at], order: { created_at: :desc },
                                                                         name: 'idx_conv_pdf_exports_on_conv_and_created'
    add_index :conversation_pdf_exports, :status
    add_index :conversation_pdf_exports, :sha256, unique: true, where: 'sha256 IS NOT NULL'
  end
end
