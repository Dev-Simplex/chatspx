# frozen_string_literal: true

FactoryBot.define do
  factory :message_sequence_step do
    message_sequence
    sequence(:position) { |n| n }
    delay_minutes { 0 }
    content { 'Olá {{contact.first_name}}!' }
  end
end
