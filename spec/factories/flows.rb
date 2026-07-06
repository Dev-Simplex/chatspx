FactoryBot.define do
  factory :flow do
    account
    sequence(:name) { |n| "Test Flow #{n}" }
    trigger_type { :manual }
    definition do
      {
        'nodes' => [
          { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => %w[vip] }
        ],
        'edges' => []
      }
    end

    trait :conversation_event do
      trigger_type { :conversation_event }
      trigger_config do
        {
          'event_name' => 'conversation_created',
          'conditions' => [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
        }
      end
    end
  end
end
