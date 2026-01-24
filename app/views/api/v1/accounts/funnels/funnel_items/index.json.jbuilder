json.array! @funnel_items do |item|
  json.partial! 'api/v1/models/funnel_item', formats: [:json], resource: item
end


