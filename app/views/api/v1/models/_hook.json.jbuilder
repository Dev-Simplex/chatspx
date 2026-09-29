json.id resource.id
json.app_id resource.app_id
json.status resource.enabled?
json.inbox resource.inbox&.slice(:id, :name)
json.account_id resource.account_id
json.hook_type resource.hook_type

if Current.account_user&.administrator?
  settings = resource.settings
  if resource.app_id == 'captador'
    settings = settings.except('shared_secret').merge('shared_secret_configured' => resource.captador_shared_secret_configured?)
  end
  json.settings settings
end
json.reference_id resource.reference_id if Current.account_user&.administrator?
