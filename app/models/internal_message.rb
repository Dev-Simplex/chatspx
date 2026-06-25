# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_messages
#
#  id                  :bigint           not null, primary key
#  content             :text             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  internal_channel_id :bigint           not null
#  user_id             :bigint           not null
#
class InternalMessage < ApplicationRecord
  belongs_to :internal_channel, inverse_of: :messages
  belongs_to :user
  has_many_attached :attachments

  validates :content, presence: true, unless: -> { attachments.attached? }

  scope :recent_first, -> { order(created_at: :desc) }
end
