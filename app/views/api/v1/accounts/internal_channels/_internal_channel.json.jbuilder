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

# On the list (index) the controller precomputes these in 2 grouped queries; on
# show (single channel) the ivars are absent, so fall back to per-channel lookups.
if defined?(@unread_counts) && @unread_counts
  json.unread_count @unread_counts[channel.id] || 0
else
  current_member = channel.members.detect { |m| m.user_id == Current.user.id }
  json.unread_count current_member&.unread_count || 0
end

last_message =
  defined?(@last_messages) && @last_messages ? @last_messages[channel.id] : channel.messages.last
if last_message.present?
  json.last_message do
    json.content last_message.content
    json.created_at last_message.created_at.to_i
    json.user_name last_message.user&.name
    json.deleted last_message.deleted?
  end
end
