# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessages::PushService do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }
  let(:carol) { create(:user, account: account, role: :agent) }

  def group_with(*users)
    create(:internal_channel, :group_chat, account: account).tap do |channel|
      users.each { |user| create(:internal_channel_member, internal_channel: channel, user: user) }
    end
  end

  def recipients_of(message)
    described_class.new(message).recipients
  end

  it 'notifies the other side of a DM, never the author' do
    dm = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
    message = create(:internal_message, internal_channel: dm, user: alice)

    expect(recipients_of(message)).to contain_exactly(bob)
  end

  it 'notifies only the mentioned people in a group' do
    group = group_with(alice, bob, carol)
    message = create(:internal_message, internal_channel: group, user: alice, mentioned_user_ids: [bob.id])

    expect(recipients_of(message)).to contain_exactly(bob)
  end

  it 'skips a muted DM, but a mention still notifies' do
    dm = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
    bob.update!(ui_settings: { 'internal_chat_muted_channel_ids' => [dm.id] })

    expect(recipients_of(create(:internal_message, internal_channel: dm, user: alice))).to be_empty
    expect(recipients_of(create(:internal_message, internal_channel: dm, user: alice, mentioned_user_ids: [bob.id]))).to contain_exactly(bob)
  end

  it 'skips who turned desktop notifications off in the chat' do
    dm = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
    bob.update!(ui_settings: { 'internal_chat_desktop_notifications' => false })

    expect(recipients_of(create(:internal_message, internal_channel: dm, user: alice))).to be_empty
  end
end
