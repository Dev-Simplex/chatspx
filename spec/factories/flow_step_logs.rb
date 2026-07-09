# frozen_string_literal: true

FactoryBot.define do
  factory :flow_step_log do
    flow
    account { flow.account }
    conversation { association(:conversation, account: flow.account) }
    node_id { 'n1' }
    action_name { 'add_label' }
    status { :success }
    duration_ms { 5 }
    # `metadata` defaults to {} at the DB level; omitted here.
  end
end
