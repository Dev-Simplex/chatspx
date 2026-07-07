require 'rails_helper'

RSpec.describe Flows::BackfillService do
  let(:account) { create(:account) }

  describe 'macros → flows' do
    let!(:macro) do
      create(:macro, account: account, name: 'Boas-vindas',
                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] },
                               { 'action_name' => 'send_message', 'action_params' => ['Oi'] }])
    end

    it 'creates a manual flow mirroring the macro actions as linear nodes' do
      described_class.new(account: account).perform
      flow = account.flows.find_by("trigger_config->>'backfill_source' = ?", "macro:#{macro.id}")
      expect(flow).to be_present
      expect(flow.trigger_type).to eq('manual')
      expect(flow.nodes.pluck('action_name')).to eq(%w[add_label send_message])
      expect(flow.edges).to eq([{ 'from' => 'n1', 'to' => 'n2' }])
      expect(flow.visibility).to eq(macro.visibility)
    end

    it 'is idempotent (does not duplicate on a second run)' do
      described_class.new(account: account).perform
      expect { described_class.new(account: account).perform }.not_to change(account.flows, :count)
    end
  end

  describe 'automation_rules → flows' do
    let(:rule_conditions) do
      [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
    end
    let!(:rule) do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: rule_conditions,
                               actions: [{ 'action_name' => 'add_label', 'action_params' => ['novo'] }])
    end

    it 'creates a conversation_event flow preserving event_name, conditions and active' do
      described_class.new(account: account).perform
      flow = account.flows.find_by("trigger_config->>'backfill_source' = ?", "automation_rule:#{rule.id}")
      expect(flow.trigger_type).to eq('conversation_event')
      expect(flow.trigger_config['event_name']).to eq('conversation_created')
      expect(flow.trigger_config['conditions']).to eq(rule_conditions)
      expect(flow.active).to eq(rule.active)
    end
  end

  describe 'dry_run' do
    before { create(:macro, account: account) }

    it 'does not create any flow' do
      expect { described_class.new(account: account, dry_run: true).perform }.not_to change(Flow, :count)
    end

    it 'reports what would be created' do
      result = described_class.new(account: account, dry_run: true).perform
      expect(result[:macros]).to eq(1)
    end
  end

  it 'does not touch the source records (non-destructive coexistence)' do
    macro = create(:macro, account: account)
    rule = create(:automation_rule, account: account)
    described_class.new(account: account).perform
    expect(macro.reload).to be_present
    expect(rule.reload.active).to be(true)
  end
end
