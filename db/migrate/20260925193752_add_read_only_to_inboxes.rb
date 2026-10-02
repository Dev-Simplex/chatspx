class AddReadOnlyToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :read_only, :boolean, default: false, null: false
    add_reference :inboxes, :read_only_redirect_inbox, foreign_key: { to_table: :inboxes, on_delete: :nullify }, null: true
  end
end
