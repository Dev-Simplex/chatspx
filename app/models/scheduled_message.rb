# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_messages
#
#  id                :bigint           not null, primary key
#  error_message     :text
#  message           :text             not null
#  scheduled_at      :datetime         not null
#  sent_at           :datetime
#  status            :integer          default("pending")
#  waha_session_name :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  conversation_id   :bigint           not null
#  inbox_id          :bigint           not null
#
# Indexes
#
#  index_scheduled_messages_on_conversation_id  (conversation_id)
#  index_scheduled_messages_on_inbox_id         (inbox_id)
#  index_scheduled_messages_on_scheduled_at     (scheduled_at)
#  index_scheduled_messages_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class ScheduledMessage < ApplicationRecord
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :message, optional: true

  validates :conversation_id, presence: true
  validates :inbox_id, presence: true
  validates :message, presence: true
  validates :scheduled_at, presence: true
  validate :scheduled_at_must_be_in_future, on: :create

  enum status: { pending: 0, sent: 1, failed: 2, cancelled: 3 }

  scope :pending, -> { where(status: :pending) }
  scope :upcoming, -> { where('scheduled_at > ?', Time.current).order(:scheduled_at) }

  def scheduled_at_must_be_in_future
    return if scheduled_at.blank?

    errors.add(:scheduled_at, 'deve ser no futuro') if scheduled_at <= Time.current
  end
end


