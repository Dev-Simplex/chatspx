# frozen_string_literal: true

# == Schema Information
#
# Table name: message_sequence_enrollments
#
#  id                    :bigint           not null, primary key
#  current_step_position :integer
#  next_run_at           :datetime
#  status                :integer          default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  conversation_id       :bigint           not null
#  enrolled_by_id        :bigint
#  message_sequence_id   :bigint           not null
#
# A conversation moving through a sequence. status active→completed when the last
# step is sent, or →cancelled when an exit condition fires (customer reply, status).
class MessageSequenceEnrollment < ApplicationRecord
  belongs_to :message_sequence, inverse_of: :enrollments
  belongs_to :conversation
  belongs_to :enrolled_by, class_name: 'User', optional: true

  enum status: { active: 0, completed: 1, cancelled: 2 }

  scope :due, -> { active.where('next_run_at <= ?', Time.current) }

  # The step this enrollment will send next (nil once past the last step).
  def current_step
    return if current_step_position.blank?

    message_sequence.steps.find_by(position: current_step_position)
  end
end
