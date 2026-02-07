# frozen_string_literal: true

class EnsureMessageColumnInScheduledMessages < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:scheduled_messages)
    return if column_exists?(:scheduled_messages, :message)

    add_column :scheduled_messages, :message, :text, null: false, default: ''
    # Se existir coluna "content", copiar para message (para tabelas criadas com nome antigo)
    if column_exists?(:scheduled_messages, :content)
      execute "UPDATE scheduled_messages SET message = COALESCE(content, '') WHERE message = '' OR message IS NULL;"
    end
  end

  def down
    return unless table_exists?(:scheduled_messages)
    return unless column_exists?(:scheduled_messages, :message)

    remove_column :scheduled_messages, :message, :text
  end
end
