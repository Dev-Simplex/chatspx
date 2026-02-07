if @funnel_stages.present?
  json.array! @funnel_stages do |stage|
    json.partial! 'api/v1/models/funnel_stage', formats: [:json], resource: stage
  end
else
  json.array! []
end
