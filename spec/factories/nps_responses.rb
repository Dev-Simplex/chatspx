# frozen_string_literal: true

FactoryBot.define do
  factory :nps_response do
    account
    conversation
    contact
    inbox
    assigned_agent { nil }
    status { :sent }
    score { nil }
    comment { nil }
    sent_at { Time.current }
    answered_at { nil }
    dismiss_reason { nil }
    blocked_by_label { nil }
    blocked_scope { nil }
    metadata { {} }

    trait :responded do
      status { :responded }
      score { rand(0..10) }
      answered_at { Time.current }
    end

    trait :expired do
      status { :expired }
      sent_at { 73.hours.ago }
    end

    trait :dismissed do
      status { :dismissed }
      dismiss_reason { 'label_blocked' }
      blocked_by_label { 'nao_avalia' }
      blocked_scope { :contact }
    end

    trait :promoter do
      status { :responded }
      score { [9, 10].sample }
      answered_at { Time.current }
    end

    trait :passive do
      status { :responded }
      score { [7, 8].sample }
      answered_at { Time.current }
    end

    trait :detractor do
      status { :responded }
      score { rand(0..6) }
      answered_at { Time.current }
    end
  end
end
