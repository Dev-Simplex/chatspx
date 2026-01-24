json.id message.id
json.content message.content
json.inbox_id message.inbox_id
json.echo_id message.echo_id if message.echo_id
json.conversation_id message.conversation.display_id
json.message_type message.message_type_before_type_cast
json.content_type message.content_type
json.status message.status
json.content_attributes message.content_attributes
json.created_at message.created_at.to_i
json.private message.private
json.source_id message.source_id
json.sender message.sender.push_event_data if message.sender
json.attachments message.attachments.map(&:push_event_data) if message.attachments.present?
json.reactions message.reactions.map do |reaction|
  json.id reaction.id
  json.message_id reaction.message_id
  json.emoji reaction.emoji
  json.user_id reaction.user_id
  json.user_type reaction.user_type
  json.created_at reaction.created_at.to_i
end if message.respond_to?(:reactions) && message.reactions.present?
json.forwarded message.forwarded if message.respond_to?(:forwarded)
json.forwarded_from_message_id message.forwarded_from_message_id if message.respond_to?(:forwarded_from_message_id)
json.starred message.starred if message.respond_to?(:starred)
