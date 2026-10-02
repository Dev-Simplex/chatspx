require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    context 'when assignee_id is blank' do
      before do
        conversation.update!(assignee: agent, assignee_agent_bot: agent_bot)
      end

      it 'clears both human and bot assignees' do
        described_class.new(conversation: conversation, assignee_id: nil).perform

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when assigning a user' do
      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
      end

      it 'sets the agent and clears agent bot' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when assigning an agent bot' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: agent_bot.id,
          assignee_type: 'AgentBot'
        )
      end

      it 'sets the agent bot and clears human assignee' do
        conversation.update!(assignee: agent, assignee_agent_bot: nil)

        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
        expect(conversation.assignee_id).to be_nil
      end
    end

    # Trava de teste (CHAT-171): assistente com only_contact_phones não assume contato fora da
    # lista — a conversa segue com quem estava, como se a IA não existisse.
    context 'when assigning a captain mirror whose assistant has the test phone lock' do
      let(:contact) { create(:contact, account: account, phone_number: '+5565999111222') }
      let(:conversation) { create(:conversation, account: account, contact: contact) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:mirror) { assistant.mirror_agent_bot }

      before { create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox) }

      def assign_mirror
        described_class.new(conversation: conversation, assignee_id: mirror.id, assignee_type: 'AgentBot').perform
      end

      it 'does not assign the mirror when the contact is outside the list' do
        assistant.update!(behavior: { 'router' => { 'only_contact_phones' => ['+5511888887777'] } })

        expect(assign_mirror).to be_nil
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'assigns the mirror when the contact is in the list' do
        assistant.update!(behavior: { 'router' => { 'only_contact_phones' => ['6599111222'] } })

        expect(assign_mirror).to eq(mirror)
        expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
      end
    end

    # Etiquetas sem IA da conta (CHAT-180): conversa ou contato etiquetado não vai para a IA.
    context 'when assigning a captain mirror and the account has labels the AI does not handle' do
      let(:conversation) { create(:conversation, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:mirror) { assistant.mirror_agent_bot }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox)
        account.update!(custom_attributes: { 'captain_etiquetas_sem_ia' => ['portaria'] })
      end

      def assign_mirror
        described_class.new(conversation: conversation, assignee_id: mirror.id, assignee_type: 'AgentBot').perform
      end

      it 'does not assign the mirror when the conversation has the label' do
        conversation.update_labels(['portaria'])

        expect(assign_mirror).to be_nil
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'does not assign the mirror when the contact has the label' do
        conversation.contact.update_labels(['portaria'])

        expect(assign_mirror).to be_nil
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'assigns the mirror when the conversation label is not configured' do
        conversation.update_labels(['vendas'])

        expect(assign_mirror).to eq(mirror)
      end
    end
  end
end
