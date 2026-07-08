# frozen_string_literal: true

FactoryBot.define do
  factory :internal_channel do
    account
    channel_type { :direct }

    trait :group_chat do
      channel_type { :group_chat }
      sequence(:name) { |n| "Equipe #{n}" }
    end

    trait :with_two_members do
      transient do
        user_a { nil }
        user_b { nil }
      end
      after(:create) do |channel, evaluator|
        a = evaluator.user_a || create(:user, account: channel.account, role: :agent)
        b = evaluator.user_b || create(:user, account: channel.account, role: :agent)
        create(:internal_channel_member, internal_channel: channel, user: a)
        create(:internal_channel_member, internal_channel: channel, user: b)
      end
    end
  end
end
