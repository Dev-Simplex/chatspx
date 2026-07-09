# frozen_string_literal: true

# == Schema Information
#
# Table name: contact_flow_suppressions
#
#  id         :bigint           not null, primary key
#  category   :string           default("marketing"), not null
#  expires_at :datetime
#  reason     :string           default("opt_out"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  contact_id :bigint           not null
#
# Indexes
#
#  index_contact_flow_suppressions_on_account_id             (account_id)
#  index_contact_flow_suppressions_on_account_id_and_category (account_id,category)
#  index_contact_flow_suppressions_on_contact_and_category   (contact_id,category) UNIQUE
#  index_contact_flow_suppressions_on_contact_id             (contact_id)
#
# "Do NOT deliver `category` messages to this contact." The Flow engine's compliance record:
# written by the opt-out handler (AutomationRuleListener, "PARAR" → marketing/opt_out) and read
# by Flows::ActionService guards before a send. `category` buckets the send (marketing vs the
# non-marketing catch-all `utility`); `all` suppresses every bucket. A suppression is honoured
# only while `active` (no expiry, or not yet expired). See ::suppressed? — the single question
# the guards ask.
class ContactFlowSuppression < ApplicationRecord
  # The send buckets. A WhatsApp MARKETING template maps to `marketing`; everything else
  # (utility/authentication/service/free-form) to `utility`. `all` matches every bucket.
  CATEGORIES = %w[marketing utility all].freeze
  # Audit only — why the row exists. Never gates ::suppressed? (an expired row already dropped
  # out of the `active` scope, whatever its reason).
  REASONS = %w[opt_out cap manual].freeze

  belongs_to :contact
  belongs_to :account

  validates :category, inclusion: { in: CATEGORIES }
  validates :reason, inclusion: { in: REASONS }
  # Mirrors the partial-free unique index [contact_id, category]: one suppression per bucket.
  validates :contact_id, uniqueness: { scope: :category }

  # In force right now: permanent (expires_at NULL) or not yet expired. Expired rows linger
  # (the unique index needs the row) but stop suppressing.
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }

  # THE guard question: is this contact currently suppressed for `category`? True when an
  # ACTIVE suppression exists for that exact bucket OR the catch-all `all`. A blank contact is
  # never suppressed (fail-open — a message with no contact is unusual and should still leave).
  def self.suppressed?(contact, category)
    return false if contact.blank?

    active.exists?(contact_id: contact.id, category: [category.to_s, 'all'])
  end

  # Idempotent opt-out ("PARAR"): upsert the (contact, category) suppression as a permanent
  # opt_out. find_or_initialize honours the unique index; the rescue converges a concurrent
  # double-"PARAR" onto the single existing row instead of raising.
  def self.record_opt_out!(contact:, account:, category: 'marketing')
    record = find_or_initialize_by(contact_id: contact.id, category: category.to_s)
    record.account ||= account
    record.reason = 'opt_out'
    record.expires_at = nil
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    find_by(contact_id: contact.id, category: category.to_s)
  end

  def active?
    expires_at.nil? || expires_at > Time.current
  end

  def expired?
    !active?
  end
end
