# frozen_string_literal: true

FactoryBot.define do
  factory :attachment_bulk_download do
    account
    requester_user { association :user, account: account }
    status { 'pending' }
    params { {} }
    audit_meta { {} }
    expires_at { 7.days.from_now }
  end
end
