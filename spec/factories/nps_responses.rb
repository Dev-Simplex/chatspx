# frozen_string_literal: true

FactoryBot.define do
  factory :nps_response do
    transient do
      conversation { nil }
    end

    status { 'responded' }
    score { 10 }
    answered_at { Time.current }
    sent_at { 1.hour.ago }

    after(:build) do |nps, evaluator|
      conversation = evaluator.conversation || create(:conversation)
      nps.account ||= conversation.account
      nps.conversation ||= conversation
      nps.contact ||= conversation.contact
      nps.inbox ||= conversation.inbox
      nps.assigned_agent ||= conversation.assignee
    end

    trait :promoter do
      score { 10 }
    end

    trait :passive do
      score { 7 }
    end

    trait :detractor do
      score { 3 }
    end
  end
end
