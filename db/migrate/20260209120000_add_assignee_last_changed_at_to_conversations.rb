# frozen_string_literal: true

class AddAssigneeLastChangedAtToConversations < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:conversations, :assignee_last_changed_at)
      add_column :conversations, :assignee_last_changed_at, :datetime
    end

    add_index :conversations, :assignee_last_changed_at unless index_exists?(:conversations, :assignee_last_changed_at)
  end
end
