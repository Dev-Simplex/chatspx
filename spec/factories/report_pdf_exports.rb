# frozen_string_literal: true

FactoryBot.define do
  factory :report_pdf_export do
    account
    report_type { 'nps' }
    status { 'pending' }
    filters { {} }
    audit_meta { {} }
  end
end
