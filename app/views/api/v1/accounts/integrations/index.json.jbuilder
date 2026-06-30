json.array! @integrations do |integration|
  json.partial! 'api/v1/accounts/integrations/integration', integration: integration
end
