# frozen_string_literal: true

FactoryBot.define do
  factory :message_reaction do
    transient do
      reactor { nil }
    end

    message { create(:message) }
    account { message&.account || create(:account) }
    emoji { '👍' }

    after(:build) do |reaction, evaluator|
      reactor = evaluator.reactor || create(:user, account: reaction.account)
      reaction.user_type = reactor.is_a?(Contact) ? 'Contact' : 'User'
      reaction.user_id = reactor.id
    end
  end
end
