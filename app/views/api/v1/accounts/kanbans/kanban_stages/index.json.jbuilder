if @kanban_stages.present?
  json.array! @kanban_stages do |stage|
    json.partial! 'api/v1/models/kanban_stage', formats: [:json], resource: stage
  end
else
  json.array! []
end
