json.array! @funnel_items do |item|
  json.id item.id
  json.funnel_id item.funnel_id
  json.funnel_name item.funnel&.name
  json.funnel_color item.funnel&.color
  json.stage_id item.funnel_stage_id
  json.stage_name item.funnel_stage&.name
  json.stage_color item.funnel_stage&.color
  json.moved_at item.moved_at
end
