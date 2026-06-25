# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessages::CreateService do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }

  it 'creates the message authored by the user' do
    message = described_class.new(channel: channel, user: alice, content: 'Olá time').perform
    expect(message).to be_persisted
    expect(message.user).to eq(alice)
    expect(message.content).to eq('Olá time')
  end

  it 'marks the channel read for the author' do
    described_class.new(channel: channel, user: alice, content: 'oi').perform
    expect(channel.members.find_by(user: alice).last_read_at).to be_present
  end

  it 'broadcasts the message to channel members in real time' do
    expect do
      described_class.new(channel: channel, user: alice, content: 'oi').perform
    end.to have_enqueued_job(ActionCableBroadcastJob)
      .with(array_including(alice.pubsub_token, bob.pubsub_token), 'internal.message.created', anything)
  end

  describe '@mentions' do
    it 'persists only mentioned members and never the author' do
      message = described_class.new(
        channel: channel, user: alice, content: 'oi @bob', mentioned_user_ids: [bob.id, alice.id]
      ).perform
      expect(message.mentioned_user_ids).to contain_exactly(bob.id)
    end

    it 'drops mentions of non-members' do
      outsider = create(:user, account: account, role: :agent)
      message = described_class.new(
        channel: channel, user: alice, content: 'oi', mentioned_user_ids: [outsider.id]
      ).perform
      expect(message.mentioned_user_ids).to be_empty
    end

    it 'broadcasts a mention event to the mentioned member' do
      expect do
        described_class.new(channel: channel, user: alice, content: 'oi @bob', mentioned_user_ids: [bob.id]).perform
      end.to have_enqueued_job(ActionCableBroadcastJob)
        .with([bob.pubsub_token], 'internal.mention.created', anything)
    end
  end
end
