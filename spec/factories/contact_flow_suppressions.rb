# frozen_string_literal: true

FactoryBot.define do
  factory :contact_flow_suppression do
    account
    contact { association :contact, account: account }
    category { 'marketing' }
    reason { 'opt_out' }
    expires_at { nil }
  end
end
