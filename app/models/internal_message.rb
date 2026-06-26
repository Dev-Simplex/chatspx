# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_messages
#
#  id                  :bigint           not null, primary key
#  content             :text             not null
#  deleted_at          :datetime
#  edited_at           :datetime
#  mentioned_user_ids  :jsonb            not null
#  reactions           :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  internal_channel_id :bigint           not null
#  user_id             :bigint           not null
#
class InternalMessage < ApplicationRecord
  belongs_to :internal_channel, inverse_of: :messages
  belongs_to :user
  has_many_attached :attachments

  validates :content, presence: true, unless: -> { attachments.attached? || deleted? }

  scope :recent_first, -> { order(created_at: :desc) }

  def deleted?
    deleted_at.present?
  end

  def edited?
    edited_at.present?
  end

  def mentions?(user)
    Array(mentioned_user_ids).map(&:to_i).include?(user.id)
  end

  # Soft-delete: keep the row (so it stays in the thread as "message deleted")
  # but drop the content and attachments.
  def soft_delete!
    attachments.purge_later
    update!(deleted_at: Time.current, content: '', mentioned_user_ids: [], reactions: {})
  end

  # Toggle an emoji reaction for a user. reactions = { emoji => [user_id, ...] }.
  def toggle_reaction!(emoji, user_id)
    data = reactions.deep_dup
    list = Array(data[emoji])
    if list.include?(user_id)
      list.delete(user_id)
    else
      list << user_id
    end
    list.empty? ? data.delete(emoji) : data[emoji] = list
    update!(reactions: data)
  end
end
