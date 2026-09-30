FactoryBot.define do
  factory :catalog_product do
    account
    sequence(:name) { |n| "Produto #{n}" }
    sequence(:sku) { |n| "SKU-#{n}" }
    description { 'Descrição do produto' }
    price_cents { 9990 }
    currency { 'BRL' }
    visible { true }

    trait :com_foto do
      after(:build) do |produto|
        produto.images.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
      end
    end
  end
end
