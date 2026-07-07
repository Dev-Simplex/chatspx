require 'rails_helper'

RSpec.describe Flow do
  let(:account) { create(:account) }

  def build_flow(nodes:, edges: [])
    build(:flow, account: account, definition: { 'nodes' => nodes, 'edges' => edges })
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:updated_by).class_name('User').optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:trigger_type).with_values(manual: 0, conversation_event: 1, schedule: 2, keyword: 3, external_webhook: 4) }
    it { is_expected.to define_enum_for(:visibility).with_values(personal: 0, global: 1) }
    it { is_expected.to define_enum_for(:reentry_policy).with_values(once: 0, re_enroll: 1, re_enroll_after: 2) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'is valid with an empty nodes/edges definition' do
      expect(build_flow(nodes: [])).to be_valid
    end

    it 'is valid with a supported action node' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['vip'] }
      expect(build_flow(nodes: [node])).to be_valid
    end

    it 'rejects a definition that is not a hash with nodes[]/edges[]' do
      flow = build(:flow, account: account, definition: { 'foo' => 'bar' })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('nodes[] and edges[]')
    end

    it 'rejects nodes whose elements are not objects (would break the walker)' do
      flow = build(:flow, account: account, definition: { 'nodes' => ['not-a-hash'], 'edges' => [] })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('nodes must be objects')
    end

    it 'rejects edges whose elements are not objects' do
      flow = build(:flow, account: account, definition: { 'nodes' => [], 'edges' => [42] })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('edges must be objects')
    end

    it 'rejects an action node with an unsupported action_name' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'do_evil' }
      flow = build_flow(nodes: [node])
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('unsupported actions').and(include('do_evil'))
    end

    it 'accepts the F1 nodes send_template and set_attribute' do
      nodes = [
        { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_template' },
        { 'id' => 'n2', 'type' => 'action', 'action_name' => 'set_attribute' }
      ]
      expect(build_flow(nodes: nodes)).to be_valid
    end

    it 'does not flag non-action nodes (trigger/condition/wait) as unsupported actions' do
      nodes = [
        { 'id' => 't1', 'type' => 'trigger' },
        { 'id' => 'c1', 'type' => 'condition', 'conditions' => [] },
        { 'id' => 'w1', 'type' => 'wait', 'params' => { 'for_minutes' => 60 } }
      ]
      expect(build_flow(nodes: nodes)).to be_valid
    end
  end

  describe '.active scope' do
    it 'returns only active flows' do
      active = create(:flow, account: account, active: true)
      create(:flow, account: account, active: false)
      expect(described_class.active).to eq([active])
    end
  end

  describe '#nodes / #edges' do
    it 'reads nodes and edges from the definition' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label' }
      flow = build_flow(nodes: [node], edges: [{ 'from' => 'n1', 'to' => nil }])
      expect(flow.nodes.first['id']).to eq('n1')
      expect(flow.edges.first['from']).to eq('n1')
    end
  end

  describe 'attachments' do
    it 'supports file attachments (preserves @macro/@rule.files for send_attachment)' do
      flow = create(:flow, account: account)
      flow.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      expect(flow.files).to be_attached
    end

    it 'exposes file_base_data for serialization' do
      flow = create(:flow, account: account)
      flow.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      data = flow.file_base_data.first
      expect(data[:flow_id]).to eq(flow.id)
      expect(data[:filename]).to eq('avatar.png')
    end
  end
end
