json.handled @stats[:handled]
json.resolved @stats[:resolved]
json.resolution_rate @stats[:resolution_rate]
json.csat @stats[:csat]
json.handoffs @stats[:handoffs]
json.series @stats[:series] do |point|
  json.date point[:date]
  json.count point[:count]
end
