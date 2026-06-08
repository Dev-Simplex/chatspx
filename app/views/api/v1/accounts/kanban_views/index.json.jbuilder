json.array! @kanban_views do |view|
  json.partial! 'api/v1/models/kanban_view', formats: [:json], resource: view
end
