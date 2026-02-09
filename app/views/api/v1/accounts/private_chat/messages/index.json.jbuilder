json.meta do
  json.conversation_id @conversation.display_id
end

json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/message', message: message
  end
end
