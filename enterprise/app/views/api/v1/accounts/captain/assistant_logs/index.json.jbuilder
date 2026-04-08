json.data do
  json.array! @logs do |log|
    json.id log.id
    json.captain_assistant_id log.captain_assistant_id
    json.conversation_id log.conversation_id
    json.message_id log.message_id
    json.event_type log.event_type
    json.payload log.payload
    json.duration_ms log.duration_ms
    json.created_at log.created_at.to_i
  end
end

json.meta do
  json.current_page @logs.current_page
  json.total_pages @logs.total_pages
  json.total_count @logs.total_count
end
