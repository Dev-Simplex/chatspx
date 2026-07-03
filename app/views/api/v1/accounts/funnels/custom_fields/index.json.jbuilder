json.array! @custom_fields do |custom_field|
  json.partial! 'api/v1/models/funnel_custom_field', formats: [:json], resource: custom_field
end
