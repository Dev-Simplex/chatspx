# frozen_string_literal: true

FactoryBot.define do
  factory :flow_run do
    flow
    account { flow.account }
    conversation { association(:conversation, account: flow.account) }
    contact { conversation.contact }
    status { :waiting }
    current_node_id { 'n2' }
    wait_until { Time.current }
    # `context` column defaults to {} at the DB level; omitted here because FactoryBot's
    # `context` attribute name collides with rubocop-rspec's example-group DSL.
  end
end
