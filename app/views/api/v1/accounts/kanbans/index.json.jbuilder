if @kanbans.present?
  json.array! @kanbans do |kanban|
    json.partial! 'api/v1/models/kanban', formats: [:json], resource: kanban
  end
else
  json.array! []
end
