json.array! @nps_responses do |nps_response|
  json.partial! 'api/v1/models/nps_response', formats: [:json], resource: nps_response
end
