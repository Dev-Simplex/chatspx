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

# Simple in-list report: enrollment counts by status.
counts = message_sequence.enrollments.group(:status).count
json.enrollment_stats do
  json.active counts['active'] || counts[0] || 0
  json.completed counts['completed'] || counts[1] || 0
  json.cancelled counts['cancelled'] || counts[2] || 0
end
