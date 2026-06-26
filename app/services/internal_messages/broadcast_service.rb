# frozen_string_literal: true

# Chat interno — pushes a message (created or updated: edit / delete / reaction)
# in real time to every channel member, reusing the RoomChannel via each user's
# pubsub_token. Single source of truth for the message payload shape.
class InternalMessages::BroadcastService
  def self.created(message)
    new(message).broadcast('internal.message.created')
  end

  def self.updated(message)
    new(message).broadcast('internal.message.updated')
  end

  def initialize(message)
    @message = message
  end

  def broadcast(event)
    tokens = @message.internal_channel.users.pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, event, payload)
  end

  def payload
    {
      internal_channel_id: @message.internal_channel_id,
      message: serialize
    }
  end

  private

  def serialize
    {
      id: @message.id,
      content: @message.deleted? ? nil : @message.content,
      created_at: @message.created_at.to_i,
      edited: @message.edited?,
      deleted: @message.deleted?,
      reactions: @message.reactions,
      reply_to: @message.reply_preview,
      shared_conversation: @message.shared_conversation_preview,
      mentioned_user_ids: @message.mentioned_user_ids,
      attachments: @message.deleted? ? [] : @message.attachments.map { |a| serialize_attachment(a) },
      user: {
        id: @message.user_id,
        name: @message.user&.name,
        avatar_url: @message.user.try(:avatar_url)
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
