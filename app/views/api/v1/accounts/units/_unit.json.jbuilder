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
  json.break_start_hour hora.break_start_hour
  json.break_start_minutes hora.break_start_minutes
  json.break_end_hour hora.break_end_hour
  json.break_end_minutes hora.break_end_minutes
end

json.exceptions unit.exceptions.sort_by(&:starts_on) do |regra|
  json.id regra.id
  json.starts_on regra.starts_on
  json.ends_on regra.ends_on
  json.name regra.name
  json.category regra.category
  json.closed_all_day regra.closed_all_day
  json.frequency regra.frequency
  json.repeat_interval regra.repeat_interval
  json.weekdays regra.weekdays
  json.week_positions regra.week_positions
  json.month_days regra.month_days
  json.until_date regra.until_date
  json.open_hour regra.open_hour
  json.open_minutes regra.open_minutes
  json.close_hour regra.close_hour
  json.close_minutes regra.close_minutes
end
