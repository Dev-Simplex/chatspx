json.array! @templates do |template|
  json.partial! 'api/v1/models/kanban_template', formats: [:json], resource: template
end
