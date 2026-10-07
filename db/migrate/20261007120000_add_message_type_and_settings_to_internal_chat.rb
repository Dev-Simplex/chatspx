class AddMessageTypeAndSettingsToInternalChat < ActiveRecord::Migration[7.1]
  # Aditiva: pedido de aprovação/ajuda (message_type 1) e aviso do sistema
  # (message_type 2, sem autor) no chat interno; settings guarda opções por canal.
  def change
    add_column :internal_messages, :message_type, :integer, default: 0, null: false
    add_column :internal_messages, :content_attributes, :jsonb, default: {}, null: false
    change_column_null :internal_messages, :user_id, true
    add_column :internal_channels, :settings, :jsonb, default: {}, null: false
  end
end
