# frozen_string_literal: true

# Posts a message into an internal channel and pushes it in real time to every
# member. Reuses the existing RoomChannel: each user already streams from their
# pubsub_token, so broadcasting to those tokens reaches their open dashboard —
# no new ActionCable channel or frontend connector needed.
class InternalMessages::CreateService
  def initialize(channel:, user:, content:, attachments: [])
    @channel = channel
    @user = user
    @content = content
    @attachments = attachments
  end

  def perform
    message = @channel.messages.new(user: @user, content: @content.to_s)
    attach!(message)
    message.save!
    mark_read!
    broadcast(message)
    message
  end

  private

  def attach!(message)
    attachable = Array(@attachments).compact.select { |a| a.is_a?(String) || a.respond_to?(:tempfile) }
    message.attachments.attach(attachable) if attachable.present?
  end

  # The author has, by definition, seen their own message.
  def mark_read!
    @channel.members.find_by(user_id: @user.id)&.update(last_read_at: Time.current)
  end

  def broadcast(message)
    tokens = @channel.users.pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, 'internal.message.created', payload(message))
  end

  def payload(message)
    {
      internal_channel_id: @channel.id,
      message: {
        id: message.id,
        content: message.content,
        created_at: message.created_at.to_i,
        user: { id: @user.id, name: @user.name, avatar_url: @user.try(:avatar_url) }
      }
    }
  end
end
