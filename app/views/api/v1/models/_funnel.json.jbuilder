json.id resource.id
json.name resource.name
json.account_id resource.account_id
json.team_id resource.team_id
json.position resource.position
json.color resource.color
json.inbox_ids resource.inbox_ids || []
json.settings resource.settings || {}
json.custom_fields resource.funnel_custom_fields.sort_by { |f| [f.position || 0, f.id] } do |custom_field|
  json.partial! 'api/v1/models/funnel_custom_field', formats: [:json], resource: custom_field
end
json.created_at resource.created_at
json.updated_at resource.updated_at
