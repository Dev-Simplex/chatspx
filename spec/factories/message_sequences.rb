# frozen_string_literal: true

FactoryBot.define do
  factory :message_sequence do
    account
    sequence(:name) { |n| "Follow-up #{n}" }
    active { true }
    exit_conditions { {} }

    trait :with_steps do
      after(:create) do |sequence|
        create(:message_sequence_step, message_sequence: sequence, position: 1, delay_minutes: 0,
                                       content: 'Olá {{contact.first_name}}, tudo bem?')
        create(:message_sequence_step, message_sequence: sequence, position: 2, delay_minutes: 60,
                                       content: 'Passando para saber se ainda tem interesse.')
      end
    end
  end
end
