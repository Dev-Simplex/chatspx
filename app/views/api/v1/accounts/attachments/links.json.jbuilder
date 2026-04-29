json.meta do
  json.total_count @messages_count
  json.current_page @current_page
  json.total_pages @total_pages
end

json.payload @messages do |message|
  conversation = message.conversation
  urls = message.content.to_s.scan(%r{https?://[^\s)]+}).first(3)

  json.id message.id
  json.content message.content
  json.urls urls
  json.created_at message.created_at.to_i

  if conversation
    json.conversation do
      json.id conversation.id
      json.display_id conversation.display_id
      json.inbox_id conversation.inbox_id
    end
  end

  json.sender message.sender.push_event_data if message.sender
end
