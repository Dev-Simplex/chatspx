class CreateReportPdfExports < ActiveRecord::Migration[7.1]
  def change
    create_table :report_pdf_exports do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :requester_user, null: true, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :report_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :filters, null: false, default: {}
      t.jsonb :audit_meta, null: false, default: {}

      t.string :sha256, limit: 64
      t.bigint :file_size

      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.text :error_message

      t.timestamps
    end

    add_index :report_pdf_exports, %i[account_id created_at], order: { created_at: :desc },
                                                              name: 'idx_report_pdf_exports_on_account_and_created'
    add_index :report_pdf_exports, %i[account_id report_type]
    add_index :report_pdf_exports, :status
  end
end
