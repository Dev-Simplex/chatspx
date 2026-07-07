require 'rails_helper'

RSpec.describe V2::Reports::AgentAssignmentBuilder do
  subject(:rows) { described_class.new(account: account, params: params).build }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: 1.day.from_now.to_i.to_s } }

  def history(**attrs)
    create(:conversation_assignment_history, account: account, conversation: conversation, **attrs)
  end

  def row_for(user)
    rows.find { |r| r[:id] == user.id }
  end

  describe '#build' do
    before do
      history(assignee: alice, assigned_by: bob, source: :manual)      # bob -> alice (manual)
      history(assignee: alice, source: :auto_round_robin)              # round-robin -> alice
      history(assignee: alice, assigned_by: alice, source: :self_assigned) # alice pega pra si
      # fora do range: NÃO deve contar
      history(assignee: alice, assigned_by: bob, source: :manual, assigned_at: 30.days.ago)
    end

    it 'returns one row per account user' do
      expect(rows.map { |r| r[:id] }).to contain_exactly(alice.id, bob.id)
    end

    it 'counts received totals and the source breakdown for the destination' do
      expect(row_for(alice)).to include(
        received_total: 3,
        received_manual: 1,
        received_auto: 1,
        self_assigned: 1
      )
    end

    it 'credits "assigned to others" to the manual author, not the destination' do
      expect(row_for(bob)[:assigned_to_others]).to eq(1)
      expect(row_for(alice)[:assigned_to_others]).to eq(0)
    end

    it 'does not count self-assignment as assigned to others' do
      expect(row_for(alice)[:self_assigned]).to eq(1)
      expect(row_for(alice)[:assigned_to_others]).to eq(0)
    end

    it 'excludes rows outside the date range' do
      # alice recebeu 4 manuais/etc no total, mas 1 está fora do range → total = 3
      expect(row_for(alice)[:received_total]).to eq(3)
      expect(row_for(bob)[:assigned_to_others]).to eq(1)
    end

    it 'includes the agent name' do
      expect(row_for(alice)[:name]).to eq(alice.name)
    end
  end
end
