json.array! @units do |unit|
  json.partial! 'unit', unit: unit
end
