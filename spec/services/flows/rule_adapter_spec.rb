require 'rails_helper'

RSpec.describe Flows::RuleAdapter do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:conditions) do
    [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
  end

  it 'exposes conditions, id and account like an AutomationRule' do
    adapter = described_class.new(conditions: conditions, flow: flow)
    expect(adapter.conditions).to eq(conditions)
    expect(adapter.id).to eq(flow.id)
    expect(adapter.account).to eq(account)
  end

  it 'defaults conditions to [] when nil' do
    expect(described_class.new(conditions: nil, flow: flow).conditions).to eq([])
  end

  it 'authorization_error! logs without raising (no Reauthorizable dependency)' do
    adapter = described_class.new(conditions: [], flow: flow)
    expect { adapter.authorization_error! }.not_to raise_error
  end

  it 'plugs into ConditionsFilterService and returns a boolean' do
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    adapter = described_class.new(conditions: conditions, flow: flow)
    result = AutomationRules::ConditionsFilterService.new(adapter, conversation, {}).perform
    expect(result).to be(true)
  end
end
