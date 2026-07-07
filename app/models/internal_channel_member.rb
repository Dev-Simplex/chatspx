# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_channel_members
#
#  id                  :bigint           not null, primary key
#  last_read_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  internal_channel_id :bigint           not null
#  user_id             :bigint           not null
#
class InternalChannelMember < ApplicationRecord
  belongs_to :internal_channel, inverse_of: :members
  belongs_to :user

  validates :user_id, uniqueness: { scope: :internal_channel_id }

  def unread_count
    scope = internal_channel.messages.where.not(user_id: user_id).where(deleted_at: nil)
    scope = scope.where('internal_messages.created_at > ?', last_read_at) if last_read_at.present?
    scope.count
  end
end
