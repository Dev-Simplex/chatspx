json.id @label.id
json.title @label.title
json.description @label.description
json.color @label.color
json.show_on_sidebar @label.show_on_sidebar
json.visibility @label.visibility
json.team_id @label.team_id
if @label.created_by
  json.created_by do
    json.id   @label.created_by.id
    json.name @label.created_by.name
  end
end
