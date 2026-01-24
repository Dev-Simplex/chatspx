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
#  index_message_reactions_on_account_id             (account_id)
#  index_message_reactions_on_message_id             (message_id)
#  index_message_reactions_on_user_type_and_user_id  (user_type,user_id)
#  index_message_reactions_unique                    (message_id,user_type,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (message_id => messages.id)
#

class MessageReaction < ApplicationRecord
  include Events::Types

  belongs_to :message
  belongs_to :account
  belongs_to :user, polymorphic: true

  validates :emoji, presence: true, length: { maximum: 10 }
  validates :user_type, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: [:message_id, :user_type], message: 'can only react once per message' }

  after_create_commit :dispatch_create_event
  after_destroy_commit :dispatch_destroy_event

  def push_event_data
    {
      id: id,
      message_id: message_id,
      emoji: emoji,
      user_id: user_id,
      user_type: user_type,
      created_at: created_at.to_i
    }
  end

  private

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(REACTION_CREATED, Time.zone.now, reaction: self)
  end

  def dispatch_destroy_event
    Rails.configuration.dispatcher.dispatch(REACTION_DELETED, Time.zone.now, reaction: self)
  end
end

