# frozen_string_literal: true

# Chat interno — pushes a message (created or updated: edit / delete / reaction)
# in real time to every channel member, reusing the RoomChannel via each user's
# pubsub_token. Single source of truth for the message payload shape.
class InternalMessages::BroadcastService
  def self.created(message)
    new(message).broadcast('internal.message.created')
  end

  # notice: aviso pronto (já traduzido) para quem pediu, quando um pedido é decidido.
  def self.updated(message, notice: nil)
    new(message, notice: notice).broadcast('internal.message.updated')
  end

  def initialize(message, notice: nil)
    @message = message
    @notice = notice
  end

  def broadcast(event)
    tokens = @message.internal_channel.users.pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, event, payload)
  end

  def payload
    {
      # account_id is required by the dashboard connector's isAValidEvent filter
      # (getCurrentAccountId === data.account_id); without it every internal.*
      # event is dropped client-side and real-time never reaches the recipient.
      account_id: @message.internal_channel.account_id,
      internal_channel_id: @message.internal_channel_id,
      message: serialize,
      notice: @notice
    }.compact
  end

  private

  def serialize
    {
      id: @message.id,
      echo_id: @message.echo_id,
      content: @message.deleted? ? nil : @message.content,
      created_at: @message.created_at.to_i,
      message_type: @message.message_type, content_attributes: @message.content_attributes,
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
