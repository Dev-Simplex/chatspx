json.dry_run @dry_run
json.summary do
  json.macros @result[:macros]
  json.automation_rules @result[:automation_rules]
  json.skipped @result[:skipped]
  json.errors @result[:errors]
end
json.flows do
  json.array! @flows do |flow|
    json.partial! 'api/v1/models/flow', formats: [:json], flow: flow
  end
end
