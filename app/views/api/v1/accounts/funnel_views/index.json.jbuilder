json.array! @funnel_views do |funnel_view|
  json.partial! 'api/v1/models/funnel_view', formats: [:json], resource: funnel_view
end
