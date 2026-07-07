# frozen_string_literal: true

# Chat interno v2 (Fase 3) — a message may share a customer conversation as a rich
# card (the differentiator vs. a generic team chat). Nullify on delete so the chat
# survives the conversation being removed. Additive.
class AddSharedConversationToInternalMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :internal_messages, :shared_conversation, null: true,
                                                            foreign_key: { to_table: :conversations, on_delete: :nullify }
  end
end
