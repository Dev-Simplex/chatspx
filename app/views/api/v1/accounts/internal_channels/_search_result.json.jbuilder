# frozen_string_literal: true

channel = message.internal_channel
json.id message.id
json.internal_channel_id message.internal_channel_id
json.channel_type channel.channel_type
json.channel_title channel.direct? ? channel.counterpart_for(Current.user)&.name : channel.name
json.content message.content
json.created_at message.created_at.to_i
json.user do
  json.id message.user_id
  json.name message.user&.name
  json.avatar_url message.user.try(:avatar_url)
end
