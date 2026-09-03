json.payload do
  json.deliveries do
    json.array! @deliveries do |delivery|
      json.id delivery.id
      json.delivery_id delivery.delivery_id
      json.event delivery.event
      json.status delivery.status
      json.http_status delivery.http_status
      json.attempts delivery.attempts
      json.error_message delivery.error_message
      json.delivered_at delivery.delivered_at
      json.created_at delivery.created_at
    end
  end
end
