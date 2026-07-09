# frozen_string_literal: true

FactoryBot.define do
  factory :canned_response do
    content { 'Content' }
    sequence(:short_code) { |n| "CODE#{n}" }
    visibility { :everyone }
    account

    trait :personal do
      visibility { :personal }
    end

    trait :team_visible do
      visibility { :team }
      team
    end

    trait :created_by do
      created_by { association :user }
    end
  end
end
