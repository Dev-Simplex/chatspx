# frozen_string_literal: true

# Chat interno v2 (Fase 2C) — reply/quote: a message may point to another message
# in the same channel. Nullify on delete so a thread survives the quoted original
# being removed. Additive.
class AddReplyToInternalMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :internal_messages, :reply_to, null: true,
                                                 foreign_key: { to_table: :internal_messages, on_delete: :nullify }
  end
end
