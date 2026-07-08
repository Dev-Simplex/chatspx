# frozen_string_literal: true

FactoryBot.define do
  factory :flow_node_stat do
    flow
    account { flow.account }
    node_id { 'n1' }
    executions { 10 }
    failures { 0 }
    period { FlowNodeStat::ALL_TIME }
  end
end
