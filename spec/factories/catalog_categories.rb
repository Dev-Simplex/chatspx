FactoryBot.define do
  factory :catalog_category do
    account
    sequence(:name) { |n| "Categoria #{n}" }
  end
end
