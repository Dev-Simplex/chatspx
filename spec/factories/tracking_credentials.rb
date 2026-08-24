# frozen_string_literal: true

FactoryBot.define do
  factory :tracking_credential do
    account
    inbox { association :inbox, account: account }
    meta_access_token { 'EAAmeta-access-token-de-teste-0001' }
    ga4_api_secret { 'ga4-api-secret-de-teste-0002' }
  end
end
