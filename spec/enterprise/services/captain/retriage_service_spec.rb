require 'rails_helper'

RSpec.describe Captain::RetriageService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'triage' => true }) }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    assistant.mirror_agent_bot
  end

  # Etiquetas sem IA da conta (CHAT-180): "Devolver para a IA" não entrega à triagem uma
  # conversa que ela não atende — ficaria muda com dono.
  describe 'etiquetas sem IA da conta' do
    before { account.update!(custom_attributes: { 'captain_etiquetas_sem_ia' => ['portaria'] }) }

    it 'returns the conversation to the triage assistant when no configured label is present (controle)' do
      result = described_class.new(conversation).call

      expect(result.success).to be true
      expect(conversation.reload.assignee_agent_bot_id).to eq(assistant.mirror_agent_bot.id)
    end

    it 'refuses when the conversation has a configured label' do
      conversation.update_labels(['portaria'])

      result = described_class.new(conversation).call

      expect(result.success).to be false
      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end
  end
end
