# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannels::FindOrCreateDmService do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }

  def perform(other)
    described_class.new(account: account, user: alice, other_user: other).perform
  end

  it 'creates a direct channel with both members' do
    channel = perform(bob)
    expect(channel).to be_direct
    expect(channel.users).to contain_exactly(alice, bob)
  end

  it 'is idempotent — returns the same channel on a second call' do
    first = perform(bob)
    expect { perform(bob) }.not_to change(InternalChannel, :count)
    expect(perform(bob)).to eq(first)
  end

  it 'returns the same channel regardless of who initiates' do
    first = perform(bob)
    second = described_class.new(account: account, user: bob, other_user: alice).perform
    expect(second).to eq(first)
  end

  it 'returns nil when starting a DM with yourself' do
    expect(perform(alice)).to be_nil
  end

  it 'returns nil for a blank counterpart' do
    expect(perform(nil)).to be_nil
  end
end
