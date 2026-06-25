# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannelMember, type: :model do
  describe 'validations' do
    it 'is unique per (channel, user)' do
      channel = create(:internal_channel)
      user = create(:user, account: channel.account, role: :agent)
      create(:internal_channel_member, internal_channel: channel, user: user)
      dup = build(:internal_channel_member, internal_channel: channel, user: user)
      expect(dup).not_to be_valid
    end
  end

  describe '#unread_count' do
    let(:account) { create(:account) }
    let(:alice) { create(:user, account: account, role: :agent) }
    let(:bob) { create(:user, account: account, role: :agent) }
    let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }
    let(:alice_member) { channel.members.find_by(user: alice) }

    it 'counts the other party messages newer than last_read_at' do
      create(:internal_message, internal_channel: channel, user: bob, content: 'oi')
      create(:internal_message, internal_channel: channel, user: bob, content: 'tudo bem?')
      expect(alice_member.unread_count).to eq(2)
    end

    it 'ignores the user own messages' do
      create(:internal_message, internal_channel: channel, user: alice, content: 'eu mesma')
      expect(alice_member.unread_count).to eq(0)
    end

    it 'respects last_read_at' do
      create(:internal_message, internal_channel: channel, user: bob, content: 'antiga')
      alice_member.update!(last_read_at: Time.current)
      create(:internal_message, internal_channel: channel, user: bob, content: 'nova')
      expect(alice_member.unread_count).to eq(1)
    end
  end
end
