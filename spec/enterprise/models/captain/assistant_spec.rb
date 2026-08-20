require 'rails_helper'

RSpec.describe Captain::Assistant do
  let(:account) { create(:account) }

  describe 'mirror agent bot lifecycle' do
    it 'creates the mirror agent bot after create' do
      assistant = create(:captain_assistant, account: account, name: 'Support IA')
      mirror = assistant.reload.agent_bot

      expect(mirror).to be_present
      expect(mirror).to be_captain
      expect(mirror.account_id).to eq(account.id)
      expect(mirror.name).to eq('Support IA')
      expect(mirror.outgoing_url).to be_nil
    end

    it 'syncs the mirror after rename' do
      assistant = create(:captain_assistant, account: account, name: 'Old Name')
      mirror = assistant.reload.agent_bot

      assistant.update!(name: 'New Name')

      expect(mirror.reload.name).to eq('New Name')
    end

    it 'syncs the mirror avatar after attach (touch)' do
      assistant = create(:captain_assistant, account: account)
      mirror = assistant.reload.agent_bot

      assistant.avatar.attach(fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

      expect(mirror.reload.avatar).to be_attached
      expect(mirror.avatar.blob_id).to eq(assistant.avatar.blob_id)
    end

    it 'destroys the mirror and nullifies assigned conversations on destroy' do
      assistant = create(:captain_assistant, account: account)
      mirror = assistant.reload.agent_bot
      conversation = create(:conversation, account: account)
      conversation.update!(assignee_agent_bot: mirror)

      assistant.destroy!

      expect(AgentBot.exists?(mirror.id)).to be false
      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end
  end

  describe '#mirror_agent_bot' do
    it 'returns the existing mirror' do
      assistant = create(:captain_assistant, account: account)
      expect(assistant.mirror_agent_bot).to eq(assistant.reload.agent_bot)
    end

    it 'recreates the mirror when missing' do
      assistant = create(:captain_assistant, account: account)
      assistant.reload.agent_bot.destroy!
      assistant.reload

      mirror = assistant.mirror_agent_bot

      expect(mirror).to be_persisted
      expect(mirror.captain_assistant_id).to eq(assistant.id)
    end
  end
end
