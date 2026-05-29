FactoryBot.define do
  factory :captain_document_chunk, class: 'Captain::DocumentChunk' do
    content { Faker::Lorem.paragraph }
    position { 0 }
    association :account
    association :assistant, factory: :captain_assistant
    document factory: :captain_document
  end
end
