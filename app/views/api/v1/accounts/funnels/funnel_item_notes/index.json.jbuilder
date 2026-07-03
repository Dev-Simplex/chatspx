json.array! @notes do |note|
  json.partial! 'api/v1/models/funnel_item_note', formats: [:json], resource: note
end
