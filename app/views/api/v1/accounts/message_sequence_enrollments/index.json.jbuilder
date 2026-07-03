json.array! @enrollments do |enrollment|
  json.partial! 'message_sequence_enrollment', message_sequence_enrollment: enrollment
end
