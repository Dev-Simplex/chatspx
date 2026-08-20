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

  describe '#agent_tools' do
    let(:assistant) { create(:captain_assistant, account: account) }

    it 'includes enabled custom tools from the assistant account' do
      custom_tool = create(:captain_custom_tool, account: account)

      tools = assistant.send(:agent_tools)

      expect(tools.map(&:name)).to include(custom_tool.slug)
      expect(tools.find { |tool| tool.name == custom_tool.slug }).to be_a(Captain::Tools::HttpTool)
    end

    it 'excludes disabled custom tools' do
      custom_tool = create(:captain_custom_tool, :disabled, account: account)

      tools = assistant.send(:agent_tools)

      expect(tools.map(&:name)).not_to include(custom_tool.slug)
    end

    it 'excludes custom tools from other accounts' do
      custom_tool = create(:captain_custom_tool)

      tools = assistant.send(:agent_tools)

      expect(tools.map(&:name)).not_to include(custom_tool.slug)
    end

    it 'keeps the built-in FAQ lookup and handoff tools' do
      tools = assistant.send(:agent_tools)

      expect(tools).to include(
        an_instance_of(Captain::Tools::FaqLookupTool),
        an_instance_of(Captain::Tools::HandoffTool)
      )
    end
  end
end
