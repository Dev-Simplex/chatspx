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
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint
#  conversation_id   :bigint           not null
#  inbox_id          :bigint           not null
#  message_id        :bigint
#  scheduled_by_id   :bigint
#
class ScheduledMessage < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :scheduled_by, class_name: 'User', optional: true
  belongs_to :sent_message,
             class_name: 'Message',
             foreign_key: :message_id,
             optional: true
  has_many_attached :attachments

  validates :conversation_id, presence: true
  validates :inbox_id, presence: true
  validate :message_or_attachments_present
  validates :scheduled_at, presence: true
  validate :scheduled_at_must_be_in_future, if: :validate_future_scheduled_at?

  enum status: { pending: 0, sent: 1, failed: 2, cancelled: 3 }

  scope :pending, -> { where(status: :pending) }
  scope :upcoming, -> { where('scheduled_at > ?', Time.current).order(:scheduled_at) }

  def scheduled_at_must_be_in_future
    return if scheduled_at.blank?

    # Tolerância de 2 min no passado: evita rejeitar por diferença de relógio ou fuso (Manaus).
    errors.add(:scheduled_at, 'deve ser no futuro') if scheduled_at <= 2.minutes.ago
  end

  def message_or_attachments_present
    return if message.present? || attachments.attached?

    errors.add(:message, 'deve ter conteúdo ou anexos')
  end

  def validate_future_scheduled_at?
    pending? && (new_record? || will_save_change_to_scheduled_at?)
  end
end
