# frozen_string_literal: true

class NormalizeScheduledMessagesStatusColumn < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:scheduled_messages)
    return unless column_exists?(:scheduled_messages, :status)

    convert_status_to_integer!
    add_status_index_if_missing
  end

  def down
    return unless table_exists?(:scheduled_messages)
    return unless column_exists?(:scheduled_messages, :status)

    convert_status_to_string!
    add_status_index_if_missing
  end

  private

  def convert_status_to_integer!
    if status_column_type == :integer
      execute <<~SQL
        UPDATE scheduled_messages
        SET status = #{status_to_integer_sql('status')};
      SQL
    else
      remove_status_index_if_present
      add_column :scheduled_messages, :status_tmp, :integer, null: false, default: 0 unless column_exists?(:scheduled_messages, :status_tmp)

      execute <<~SQL
        UPDATE scheduled_messages
        SET status_tmp = #{status_to_integer_sql('status')};
      SQL

      remove_column :scheduled_messages, :status
      rename_column :scheduled_messages, :status_tmp, :status
    end

    change_column_default :scheduled_messages, :status, 0
    change_column_null :scheduled_messages, :status, false, 0
  end

  def convert_status_to_string!
    if status_column_type == :string
      execute <<~SQL
        UPDATE scheduled_messages
        SET status = #{status_to_string_sql('status')};
      SQL
    else
      remove_status_index_if_present
      add_column :scheduled_messages, :status_tmp, :string, null: false, default: 'pending' unless column_exists?(:scheduled_messages, :status_tmp)

      execute <<~SQL
        UPDATE scheduled_messages
        SET status_tmp = #{status_to_string_sql('status')};
      SQL

      remove_column :scheduled_messages, :status
      rename_column :scheduled_messages, :status_tmp, :status
    end

    change_column_default :scheduled_messages, :status, 'pending'
    change_column_null :scheduled_messages, :status, false, 'pending'
  end

  def status_column_type
    connection.columns(:scheduled_messages).find { |column| column.name == 'status' }&.type
  end

  def status_to_integer_sql(column_name)
    <<~SQL.squish
      CASE
        WHEN #{column_name} IS NULL THEN 0
        WHEN lower(trim(#{column_name}::text)) IN ('0', 'pending') THEN 0
        WHEN lower(trim(#{column_name}::text)) IN ('1', 'sent') THEN 1
        WHEN lower(trim(#{column_name}::text)) IN ('2', 'failed') THEN 2
        WHEN lower(trim(#{column_name}::text)) IN ('3', 'cancelled', 'canceled') THEN 3
        ELSE 0
      END
    SQL
  end

  def status_to_string_sql(column_name)
    <<~SQL.squish
      CASE
        WHEN lower(trim(#{column_name}::text)) IN ('0', 'pending') THEN 'pending'
        WHEN lower(trim(#{column_name}::text)) IN ('1', 'sent') THEN 'sent'
        WHEN lower(trim(#{column_name}::text)) IN ('2', 'failed') THEN 'failed'
        WHEN lower(trim(#{column_name}::text)) IN ('3', 'cancelled', 'canceled') THEN 'cancelled'
        ELSE 'pending'
      END
    SQL
  end

  def remove_status_index_if_present
    remove_index :scheduled_messages, :status if index_exists?(:scheduled_messages, :status)
  end

  def add_status_index_if_missing
    add_index :scheduled_messages, :status unless index_exists?(:scheduled_messages, :status)
  end
end
