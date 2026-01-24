json.id resource.id
json.content resource.content
json.message_type resource.message_type_before_type_cast
json.content_type resource.content_type
json.content_attributes resource.content_attributes
json.created_at resource.created_at.to_i
json.conversation_id resource.conversation.display_id
json.attachments resource.attachments.map(&:push_event_data) if resource.attachments.present?
json.sender resource.sender.push_event_data if resource.sender
json.reactions resource.reactions.map do |reaction|
  json.id reaction.id
  json.message_id reaction.message_id
  json.emoji reaction.emoji
  json.user_id reaction.user_id
  json.user_type reaction.user_type
  json.created_at reaction.created_at.to_i
end if resource.respond_to?(:reactions) && resource.reactions.present?
json.forwarded resource.forwarded if resource.respond_to?(:forwarded)
json.forwarded_from_message_id resource.forwarded_from_message_id if resource.respond_to?(:forwarded_from_message_id)
json.starred resource.starred if resource.respond_to?(:starred)
