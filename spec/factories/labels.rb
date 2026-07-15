# frozen_string_literal: true

FactoryBot.define do
  factory :label do
    account
    sequence(:title) { |n| "Label_#{n}" }
    visibility { :everyone }

    trait :personal do
      visibility { :personal }
    end

    trait :team_visible do
      visibility { :team }
      team { association :team, account: account }
    end

    trait :created_by do
      created_by { association :user, account: account }
    end
  end
end
