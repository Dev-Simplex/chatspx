# frozen_string_literal: true

# Compliance backbone for the Flow engine (WhatsApp marketing, gap-BR). ONE row = "do NOT
# deliver messages of this `category` to this contact". Written by the opt-out handler
# ("PARAR" → category:marketing, reason:opt_out) and readable by future manual/admin
# suppressions (reason:manual) or scheduled ones (`expires_at`). Consumed by
# Flows::ActionService guards right before send_message/send_template leave the engine.
#
# `category` (marketing/utility/all): the send bucket a template maps to (WhatsApp MARKETING →
# marketing; everything else → utility). `all` is a catch-all that suppresses every bucket.
# `reason` (opt_out/cap/manual): why it exists — audit only, never gates the check. `expires_at`
# nullable = permanent; a future timestamp = temporary (the `active` scope filters expired).
# Unique [contact_id, category] keeps at most one suppression per bucket per contact (a repeat
# "PARAR" is idempotent). Mirrors the create_flow_runs migration's shape/style.
class CreateContactFlowSuppressions < ActiveRecord::Migration[7.1]
  def change
    create_table :contact_flow_suppressions do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string   :category, null: false, default: 'marketing' # marketing / utility / all
      t.string   :reason, null: false, default: 'opt_out'      # opt_out / cap / manual
      t.datetime :expires_at                                   # null = permanent; future = temporary
      t.timestamps
    end

    add_index :contact_flow_suppressions,
              [:contact_id, :category],
              unique: true,
              name: 'index_contact_flow_suppressions_on_contact_and_category'
    add_index :contact_flow_suppressions, [:account_id, :category]
  end
end
