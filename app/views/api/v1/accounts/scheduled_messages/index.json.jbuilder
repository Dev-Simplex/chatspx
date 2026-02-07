json.array! @scheduled_messages do |message|
  json.partial! 'api/v1/models/scheduled_message', formats: [:json], resource: message
end
