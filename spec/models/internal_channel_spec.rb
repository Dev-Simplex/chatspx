# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannel, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:team).optional }
    it { is_expected.to have_many(:members).dependent(:destroy) }
    it { is_expected.to have_many(:messages).dependent(:destroy) }
  end

  describe 'enum channel_type' do
    it { expect(described_class.channel_types).to eq('direct' => 0, 'group_chat' => 1, 'team' => 2) }
  end

  describe 'name validation' do
    it 'requires a name for non-direct channels' do
      channel = build(:internal_channel, channel_type: :group_chat, name: nil)
      expect(channel).not_to be_valid
    end

    it 'does not require a name for a DM' do
      expect(build(:internal_channel, channel_type: :direct, name: nil)).to be_valid
    end
  end

  describe '#counterpart_for' do
    let(:account) { create(:account) }
    let(:alice) { create(:user, account: account, role: :agent) }
    let(:bob) { create(:user, account: account, role: :agent) }

    it 'returns the other member of a DM' do
      channel = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
      expect(channel.counterpart_for(alice)).to eq(bob)
      expect(channel.counterpart_for(bob)).to eq(alice)
    end
  end
end
