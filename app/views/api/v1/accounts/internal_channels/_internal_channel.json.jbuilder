# frozen_string_literal: true

json.id channel.id
json.channel_type channel.channel_type
json.title channel.direct? ? channel.counterpart_for(Current.user)&.name : channel.name

json.members channel.members do |m|
  json.id m.user_id
  json.name m.user&.name
  json.avatar_url m.user.try(:avatar_url)
  json.last_read_at m.last_read_at&.to_i
end

current_member = channel.members.detect { |m| m.user_id == Current.user.id }
json.unread_count current_member&.unread_count || 0

last_message = channel.messages.last
if last_message.present?
  json.last_message do
    json.content last_message.content
    json.created_at last_message.created_at.to_i
    json.user_name last_message.user&.name
  end
end
