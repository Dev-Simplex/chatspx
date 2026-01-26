json.partial! 'api/v1/models/account', formats: [:json], resource: @account
json.latest_chatwoot_version @latest_chatwoot_version
json.maintenance_banner @maintenance_banner || { enabled: false }
json.update_banner @update_banner || { enabled: false }
json.partial! 'enterprise/api/v1/accounts/partials/account', account: @account if ChatwootApp.enterprise?
