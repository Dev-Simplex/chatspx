json.id message_sequence.id
json.name message_sequence.name
json.active message_sequence.active
json.exit_conditions message_sequence.exit_conditions
json.created_at message_sequence.created_at
json.updated_at message_sequence.updated_at

json.steps message_sequence.steps do |step|
  json.id step.id
  json.position step.position
  json.delay_minutes step.delay_minutes
  json.content step.content
  json.has_template_params step.template_params.present?
end
