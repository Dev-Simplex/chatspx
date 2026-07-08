# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_channels
#
#  id           :bigint           not null, primary key
#  channel_type :integer          default(0), not null
#  name         :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  team_id      :bigint
#
# Chat interno (Módulo B): an agent↔agent / team conversation space.
class InternalChannel < ApplicationRecord
  belongs_to :account
  belongs_to :team, optional: true
  has_many :members, class_name: 'InternalChannelMember', dependent: :destroy, inverse_of: :internal_channel
  has_many :users, through: :members
  has_many :messages, -> { order(:created_at) },
           class_name: 'InternalMessage', dependent: :destroy, inverse_of: :internal_channel

  # NB: 'group' would clash with ActiveRecord's .group — use group_chat.
  enum channel_type: { direct: 0, group_chat: 1, team: 2 }

  validates :name, presence: true, unless: :direct?

  scope :for_user, ->(user) { joins(:members).where(internal_channel_members: { user_id: user.id }) }

  # The other participant in a DM, from a given user's perspective (for the title).
  # Uses the loaded collection (detect) to stay friendly with includes(:users).
  def counterpart_for(user)
    return unless direct?

    users.detect { |member| member.id != user.id }
  end
end
