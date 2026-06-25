# frozen_string_literal: true

# Chat interno (Módulo B) — a space for agent↔agent / team conversation, separate
# from customer service. A channel is a DM (1:1), a group, or a team mirror. New
# tables → additive, reversible, inert until the internal_chat flag is on.
class CreateInternalChannels < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_channels do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name # nil for a DM (named from the other member)
      t.integer :channel_type, null: false, default: 0 # direct / group / team
      t.references :team, foreign_key: true # set when the channel mirrors a Team
      t.timestamps
    end
    add_index :internal_channels, [:account_id, :channel_type]
  end
end
