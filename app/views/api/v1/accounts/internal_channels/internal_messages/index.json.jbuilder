# frozen_string_literal: true

json.array! @messages do |message|
  json.partial! 'api/v1/accounts/internal_channels/internal_messages/internal_message', message: message
end
