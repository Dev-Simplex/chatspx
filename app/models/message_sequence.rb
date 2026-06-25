# frozen_string_literal: true

# == Schema Information
#
# Table name: message_sequences
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  exit_conditions :jsonb            not null
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#
# Follow-up drip (Módulo A): a named, configurable sequence of messages. Generalizes
# Spx::Tozi::ReactivationCadenceService — steps/timings are data, not hardcoded.
class MessageSequence < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :steps, -> { order(:position) },
           class_name: 'MessageSequenceStep', dependent: :destroy, inverse_of: :message_sequence
  has_many :enrollments,
           class_name: 'MessageSequenceEnrollment', dependent: :destroy, inverse_of: :message_sequence
  accepts_nested_attributes_for :steps, allow_destroy: true

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  # Should the drip stop when the customer replies? (default: yes — a reply means
  # the human took over; mirrors ReactivationCadenceService.cancel_pending.)
  def cancel_on_customer_reply?
    exit_conditions.fetch('on_customer_reply', true)
  end

  # Optional conversation status that ends the sequence (e.g. 'resolved').
  def exit_status
    exit_conditions['on_status'].presence
  end
end
