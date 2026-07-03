json.id resource.id
json.funnel_item_id resource.funnel_item_id
json.content resource.content
json.created_at resource.created_at
json.user_id resource.user_id
if resource.user.present?
  json.user do
    json.id resource.user.id
    json.name resource.user.available_name || resource.user.name
    json.thumbnail resource.user.avatar_url
  end
end
