# frozen_string_literal: true

# Chat interno (Módulo B, B2) — persist which members were @mentioned so the
# highlight survives a reload. Additive, reversible.
class AddMentionsToInternalMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_messages, :mentioned_user_ids, :jsonb, null: false, default: []
  end
end
