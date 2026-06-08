json.id resource.display_id
json.uuid resource.uuid
json.inbox_id resource.inbox_id
json.contact_last_seen_at resource.contact_last_seen_at.to_i
json.status resource.status
json.agent_last_seen_at resource.agent_last_seen_at.to_i
json.messages do
  # Limita a serializacao as ultimas 100 mensagens para evitar timeout
  # em conversas longas (o widget carrega mais via /messages com paginacao).
  json.array! resource.messages.chat.last(100) do |message|
    json.partial! 'public/api/v1/models/message', formats: [:json], resource: message
  end
end
json.contact resource.contact
