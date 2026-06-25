# frozen_string_literal: true

FactoryBot.define do
  factory :internal_channel_member do
    internal_channel
    user
  end
end
