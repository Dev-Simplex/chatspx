json.id request.id
json.status request.status
json.resolution_source request.resolution_source
json.reason request.reason
json.response_note request.response_note
json.created_at request.created_at.to_i
json.responded_at request.responded_at&.to_i
json.conversation_id request.conversation&.display_id

if request.requester
  json.requester do
    json.id request.requester.id
    json.name request.requester.available_name
    json.thumbnail request.requester.avatar_url
  end
end

if request.owner
  json.owner do
    json.id request.owner.id
    json.name request.owner.available_name
    json.thumbnail request.owner.avatar_url
  end
end

# Contato/caixa só como metadado, sem trecho de conversa (mesma regra da aba).
if request.conversation&.contact
  json.contact do
    json.id request.conversation.contact.id
    json.name request.conversation.contact.name
    json.thumbnail request.conversation.contact.avatar_url
  end
end
