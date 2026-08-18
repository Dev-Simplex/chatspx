# frozen_string_literal: true

FactoryBot.define do
  factory :widget_partial_lead do
    account
    inbox { association(:inbox, account: account) }
    sequence(:session_id) { |n| "session-#{n}" }
    answers { { 'fullName' => 'Walisson', 'emailAddress' => 'walisson@empresa.com.br' } }
    step_reached { 3 }
    step_key { 'phoneNumber' }
    last_answered_at { Time.current }
  end
end
