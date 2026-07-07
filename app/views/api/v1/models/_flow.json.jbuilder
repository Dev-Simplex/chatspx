json.id flow.id
json.name flow.name
json.description flow.description
json.trigger_type flow.trigger_type
json.trigger_config flow.trigger_config
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
