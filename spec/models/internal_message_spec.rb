# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessage, type: :model do
  let(:account) { create(:account) }
  let(:channel) { create(:internal_channel, :with_two_members, account: account) }
  let(:author) { channel.users.first }
  let(:message) { create(:internal_message, internal_channel: channel, user: author, content: 'oi') }

  describe '#soft_delete!' do
    it 'marks as deleted and clears the content' do
      message.soft_delete!
      expect(message.reload).to be_deleted
      expect(message.content).to eq('')
    end
  end

  describe '#edited?' do
    it 'reflects edited_at' do
      expect(message).not_to be_edited
      message.update!(content: 'oi editado', edited_at: Time.current)
      expect(message.reload).to be_edited
    end
  end

  describe '#toggle_reaction!' do
    it 'adds, then removes a reaction for a user' do
      message.toggle_reaction!('👍', author.id)
      expect(message.reload.reactions).to eq('👍' => [author.id])

      message.toggle_reaction!('👍', author.id)
      expect(message.reload.reactions).to eq({})
    end

    it 'accumulates different users on the same emoji' do
      other = channel.users.last
      message.toggle_reaction!('❤️', author.id)
      message.toggle_reaction!('❤️', other.id)
      expect(message.reload.reactions['❤️']).to contain_exactly(author.id, other.id)
    end
  end
end
