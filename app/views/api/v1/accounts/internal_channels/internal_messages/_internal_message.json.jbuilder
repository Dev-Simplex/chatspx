# frozen_string_literal: true

json.id message.id
json.internal_channel_id message.internal_channel_id
json.content message.content
json.created_at message.created_at.to_i
json.user do
  json.id message.user_id
  json.name message.user&.name
  json.avatar_url message.user.try(:avatar_url)
end
json.attachments(message.attachments.map do |attachment|
  blob = attachment.blob
  {
    id: attachment.id,
    filename: blob.filename.to_s,
    url: rails_blob_path(blob, only_path: true)
  }
end)
