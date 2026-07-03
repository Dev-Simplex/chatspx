# frozen_string_literal: true

# == Schema Information
#
# Table name: message_sequence_steps
#
#  id                  :bigint           not null, primary key
#  content             :text
#  delay_minutes       :integer          default(0), not null
#  position            :integer          not null
#  template_params     :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  message_sequence_id :bigint           not null
#
# One message in a sequence. delay_minutes is the wait BEFORE this step, measured
# from the previous step's send (or from enrollment for the first step).
class MessageSequenceStep < ApplicationRecord
  belongs_to :message_sequence, inverse_of: :steps

  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :delay_minutes, numericality: { greater_than_or_equal_to: 0 }
  # The visible text is required: the send pipeline (ScheduledMessage) needs content
  # or attachments; template_params alone (HSM) still rides on top of a preview text,
  # exactly like ReactivationCadenceService.
  validates :content, presence: true

  # Interpolate {{contact.name}} (and a couple of friendly aliases) for a conversation.
  def render_content(conversation)
    name = conversation&.contact&.name.presence || ''
    first_name = name.to_s.split.first || ''
    content.to_s
           .gsub('{{contact.name}}', name)
           .gsub('{{contact.first_name}}', first_name)
  end
end
