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

  describe 'attachment size validation' do
    let(:upload) do
      Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    end

    it 'rejects an attachment above the size cap' do
      stub_const('InternalMessage::MAX_ATTACHMENT_SIZE', 1)
      msg = channel.messages.new(user: author, content: 'arquivo')
      msg.attachments.attach(upload)
      expect(msg).not_to be_valid
      expect(msg.errors[:attachments]).to be_present
    end

    it 'accepts an attachment within the size cap' do
      msg = channel.messages.new(user: author, content: 'arquivo')
      msg.attachments.attach(upload)
      expect(msg).to be_valid
    end
  end
end
