json.payload do
  json.array! @flows do |flow|
    json.partial! 'api/v1/models/flow', formats: [:json], flow: flow
  end
end
