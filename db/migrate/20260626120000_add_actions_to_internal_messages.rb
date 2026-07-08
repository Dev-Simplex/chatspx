# frozen_string_literal: true

# Chat interno v2 (Fase 2A) — message actions: edit (edited_at), soft-delete
# (deleted_at) and emoji reactions (jsonb { "👍" => [user_id, ...] }). Additive.
class AddActionsToInternalMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_messages, :edited_at, :datetime
    add_column :internal_messages, :deleted_at, :datetime
    add_column :internal_messages, :reactions, :jsonb, null: false, default: {}
  end
end
