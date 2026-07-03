json.array! @automations do |automation|
  json.partial! 'api/v1/models/funnel_automation', formats: [:json], resource: automation
end
