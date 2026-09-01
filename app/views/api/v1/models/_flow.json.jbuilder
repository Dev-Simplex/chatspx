json.id flow.id
json.name flow.name
json.description flow.description
json.trigger_type flow.trigger_type
# O `webhook_token` dentro do trigger_config é a credencial do endpoint PÚBLICO
# (Webhooks::FlowsController) — quem o tem dispara o flow de fora, sem sessão. Um flow `global`
# aparece para a conta inteira, então o token sai só para o AUTOR e para o ADMINISTRADOR (quem
# pode editá-lo); para os demais a chave é omitida. Ver Flow#trigger_config_for.
json.trigger_config flow.trigger_config_for(Current.user, Current.account_user)
json.definition flow.definition
json.active flow.active
json.version flow.version
json.visibility flow.visibility

if flow.created_by.present?
  json.created_by do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: flow.created_by
  end
end

if flow.updated_by.present?
  json.updated_by do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: flow.updated_by
  end
end

json.account_id flow.account_id
json.files flow.file_base_data if flow.files.any?
