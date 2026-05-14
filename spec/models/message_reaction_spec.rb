require 'rails_helper'

RSpec.describe MessageReaction do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:message) { create(:message, account: account) }

  describe 'associations' do
    it { is_expected.to belong_to(:message) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject(:reaction) do
      described_class.new(
        message: message,
        account: account,
        emoji: '👍',
        user_type: 'User',
        user_id: user.id
      )
    end

    it 'is valid with default attributes' do
      expect(reaction).to be_valid
    end

    it 'requires an emoji' do
      reaction.emoji = nil
      expect(reaction).not_to be_valid
      expect(reaction.errors[:emoji]).to include("can't be blank")
    end

    it 'rejects emoji longer than 10 chars' do
      reaction.emoji = 'a' * 11
      expect(reaction).not_to be_valid
      expect(reaction.errors[:emoji]).to be_present
    end

    it 'rejects unknown user_type' do
      reaction.user_type = 'AgentBot'
      expect(reaction).not_to be_valid
      expect(reaction.errors[:user_type]).to be_present
    end

    it 'accepts Contact as user_type' do
      contact = create(:contact, account: account)
      reaction.user_type = 'Contact'
      reaction.user_id = contact.id
      expect(reaction).to be_valid
    end

    it 'enforces uniqueness of (message_id, user_type, user_id)' do
      described_class.create!(message: message, account: account, emoji: '👍', user_type: 'User', user_id: user.id)
      duplicate = described_class.new(message: message, account: account, emoji: '❤️', user_type: 'User', user_id: user.id)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end
  end

  describe '#push_event_data' do
    let(:reaction) do
      create(:message_reaction, message: message, account: account, reactor: user, emoji: '🔥')
    end

    it 'serializes id, message_id, emoji and user attribution' do
      data = reaction.push_event_data
      expect(data).to include(
        id: reaction.id,
        message_id: message.id,
        emoji: '🔥',
        user_id: user.id,
        user_type: 'User',
        user_name: user.name
      )
      expect(data[:created_at]).to be_an(Integer)
    end
  end

  describe '#user_display_name' do
    it 'returns user.name when present' do
      reaction = build(:message_reaction, message: message, account: account, reactor: user)
      expect(reaction.user_display_name).to eq(user.name)
    end
  end
end
