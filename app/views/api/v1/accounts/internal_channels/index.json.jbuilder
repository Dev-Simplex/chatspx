# frozen_string_literal: true

json.array! @channels do |channel|
  json.partial! 'api/v1/accounts/internal_channels/internal_channel', channel: channel
end
