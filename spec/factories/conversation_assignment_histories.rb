# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_assignment_history do
    account
    conversation
    assignee { nil }
    assigned_by { nil }
    team { nil }
    source { :manual }
    assigned_at { Time.current }
  end
end
