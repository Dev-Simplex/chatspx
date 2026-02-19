if @meta.present?
  json.payload do
    json.array! @scheduled_messages do |message|
      json.partial! 'api/v1/models/scheduled_message', formats: [:json], resource: message
    end
  end

  json.meta do
    json.has_more @meta[:has_more]
    json.next_cursor @meta[:next_cursor]
    json.limit @meta[:limit]
    json.status @meta[:status]
    json.from @meta[:from]
    json.to @meta[:to]
  end
else
  json.array! @scheduled_messages do |message|
    json.partial! 'api/v1/models/scheduled_message', formats: [:json], resource: message
  end
end
