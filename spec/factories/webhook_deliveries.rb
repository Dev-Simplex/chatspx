FactoryBot.define do
  factory :webhook_delivery do
    webhook
    account { webhook.account }
    delivery_id { SecureRandom.uuid }
    event { 'conversation_created' }
    status { :delivered }
    payload { { 'event' => 'conversation_created' } }
  end
end
