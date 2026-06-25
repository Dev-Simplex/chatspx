# frozen_string_literal: true

# Posts a message into an internal channel and pushes it in real time to every
# member. Reuses the existing RoomChannel: each user already streams from their
# pubsub_token, so broadcasting to those tokens reaches their open dashboard —
# no new ActionCable channel or frontend connector needed.
#
# @mentions (B2): persisted on the message and delivered as a distinct real-time
# event to the mentioned members (toast + badge). We deliberately do NOT route
# these through the global notification bell — that is hardwired to Conversation
# primary actors (closed enum + /conversations navigation), so reusing it would
# mean invasive, broad-impact changes to core. Real-time delivery covers the need.
class InternalMessages::CreateService
  def initialize(channel:, user:, content:, attachments: [], mentioned_user_ids: [])
    @channel = channel
    @user = user
    @content = content
    @attachments = attachments
    @mentioned_user_ids = Array(mentioned_user_ids).map(&:to_i)
  end

  def perform
    message = @channel.messages.new(user: @user, content: @content.to_s, mentioned_user_ids: valid_mentions)
    attach!(message)
    message.save!
    mark_read!
    broadcast(message)
    broadcast_mentions(message)
    message
  end

  private

  # Only members of this channel can be mentioned, and never the author.
  def valid_mentions
    return [] if @mentioned_user_ids.blank?

    member_ids = @channel.members.pluck(:user_id)
    (@mentioned_user_ids & member_ids) - [@user.id]
  end

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

  def broadcast_mentions(message)
    return if message.mentioned_user_ids.blank?

    tokens = User.where(id: message.mentioned_user_ids).pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, 'internal.mention.created', {
                                            internal_channel_id: @channel.id,
                                            channel_title: @channel.direct? ? @user.name : @channel.name,
                                            from: @user.name
                                          })
  end

  def payload(message)
    {
      internal_channel_id: @channel.id,
      message: {
        id: message.id,
        content: message.content,
        created_at: message.created_at.to_i,
        mentioned_user_ids: message.mentioned_user_ids,
        attachments: message.attachments.map { |a| serialize_attachment(a) },
        user: { id: @user.id, name: @user.name, avatar_url: @user.try(:avatar_url) }
      }
    }
  end

  def serialize_attachment(attachment)
    {
      id: attachment.id,
      filename: attachment.blob.filename.to_s,
      url: Rails.application.routes.url_helpers.rails_blob_path(attachment.blob, only_path: true)
    }
  end
end
