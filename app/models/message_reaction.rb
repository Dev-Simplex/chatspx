# == Schema Information
#
# Table name: message_reactions
#
#  id         :bigint           not null, primary key
#  emoji      :string(10)       not null
#  user_type  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  message_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_message_reactions_on_account_id              (account_id)
#  index_message_reactions_on_message_id              (message_id)
#  index_message_reactions_on_user_type_and_user_id   (user_type,user_id)
#  index_message_reactions_unique                     (message_id,user_type,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#

# Persisted per-user emoji reactions on Messages (PR B1).
#
# Each row is a single reaction by one user (or contact) on one message. The
# unique index ensures a (message, user_type, user_id) triple may only have a
# single reaction at a time — when a user reacts again with a different emoji
# the existing row is UPDATEd in place (controller-side), not duplicated.
class MessageReaction < ApplicationRecord
  USER_TYPES = %w[User Contact].freeze

  belongs_to :message
  belongs_to :account
  # Polymorphic-style user reference. We intentionally avoid a `belongs_to`
  # polymorphic because we want to support exactly two concrete classes
  # (User and Contact) and to keep query plans cheap via the explicit index.
  belongs_to :user, polymorphic: true

  validates :emoji, presence: true, length: { maximum: 10 }
  validates :user_type, presence: true, inclusion: { in: USER_TYPES }
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: %i[message_id user_type] }

  scope :for_message, ->(message_id) { where(message_id: message_id) }

  def push_event_data
    {
      id: id,
      message_id: message_id,
      emoji: emoji,
      user_id: user_id,
      user_type: user_type,
      user_name: user_display_name,
      created_at: created_at.to_i
    }
  end

  def user_display_name
    return user.try(:name) if user.respond_to?(:name)

    nil
  end
end
