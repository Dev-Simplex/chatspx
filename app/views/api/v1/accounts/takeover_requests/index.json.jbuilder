json.payload do
  json.array! @takeover_requests do |request|
    json.partial! 'api/v1/accounts/takeover_requests/takeover_request', request: request
  end
end
