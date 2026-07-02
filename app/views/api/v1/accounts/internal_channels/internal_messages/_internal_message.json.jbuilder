# frozen_string_literal: true

json.id message.id
json.echo_id message.echo_id
json.internal_channel_id message.internal_channel_id
json.content message.deleted? ? nil : message.content
json.created_at message.created_at.to_i
json.edited message.edited?
json.deleted message.deleted?
json.reactions message.reactions
json.reply_to message.reply_preview
json.shared_conversation message.shared_conversation_preview
json.mentioned_user_ids message.mentioned_user_ids
json.user do
  json.id message.user_id
  json.name message.user&.name
  json.avatar_url message.user.try(:avatar_url)
end
json.attachments(message.deleted? ? [] : message.attachments.map do |attachment|
  blob = attachment.blob
  {
    id: attachment.id,
    filename: blob.filename.to_s,
    url: rails_blob_path(blob, only_path: true)
  }
end)
