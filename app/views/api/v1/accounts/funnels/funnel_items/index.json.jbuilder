if @meta.present?
  json.payload do
    json.array! @funnel_items do |item|
      json.partial! 'api/v1/models/funnel_item', formats: [:json], resource: item
    end
  end

  json.meta do
    json.stage_id @meta[:stage_id]
    json.has_more @meta[:has_more]
    json.next_cursor @meta[:next_cursor]
    json.limit @meta[:limit]
  end
else
  json.array! @funnel_items do |item|
    json.partial! 'api/v1/models/funnel_item', formats: [:json], resource: item
  end
end
