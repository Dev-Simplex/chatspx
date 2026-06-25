# frozen_string_literal: true

json.array! @agents do |agent|
  json.id agent.id
  json.name agent.name
  json.email agent.email
  json.avatar_url agent.try(:avatar_url)
end
