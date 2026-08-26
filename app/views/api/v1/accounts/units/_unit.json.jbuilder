json.id unit.id
json.name unit.name
json.city unit.city
json.state unit.state
json.address unit.address
json.phone unit.phone
json.timezone unit.timezone
json.notes unit.notes
json.active unit.active
json.created_at unit.created_at
json.updated_at unit.updated_at

# Caixas desta unidade — a tela mostra quais linhas atendem por aqui.
json.inbox_ids unit.inboxes.map(&:id)

json.working_hours unit.working_hours.sort_by(&:day_of_week) do |hora|
  json.id hora.id
  json.day_of_week hora.day_of_week
  json.closed_all_day hora.closed_all_day
  json.open_all_day hora.open_all_day
  json.open_hour hora.open_hour
  json.open_minutes hora.open_minutes
  json.close_hour hora.close_hour
  json.close_minutes hora.close_minutes
end

json.exceptions unit.exceptions.sort_by(&:date) do |excecao|
  json.id excecao.id
  json.date excecao.date
  json.name excecao.name
  json.closed_all_day excecao.closed_all_day
  json.annual excecao.annual
  json.open_hour excecao.open_hour
  json.open_minutes excecao.open_minutes
  json.close_hour excecao.close_hour
  json.close_minutes excecao.close_minutes
end
