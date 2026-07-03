# frozen_string_literal: true

FactoryBot.define do
  factory :message_sequence_enrollment do
    message_sequence
    conversation
    status { :active }
    current_step_position { 1 }
    next_run_at { Time.current }
  end
end
