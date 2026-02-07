json.id resource.id
json.conversation_id resource.conversation_id
json.conversation_display_id resource.conversation&.display_id
json.inbox_id resource.inbox_id
json.message resource.try(:message).to_s
json.scheduled_at resource.scheduled_at&.iso8601
json.status resource.status
json.sent_at resource.respond_to?(:sent_at) ? resource.sent_at&.iso8601 : nil
json.error_message resource.respond_to?(:error_message) ? resource.error_message : nil
if resource.respond_to?(:scheduled_by_id) && resource.scheduled_by.present?
  json.scheduled_by do
    json.id resource.scheduled_by.id
    json.name resource.scheduled_by.name
  end
else
  json.scheduled_by nil
end
json.created_at resource.created_at&.iso8601
json.updated_at resource.updated_at&.iso8601
