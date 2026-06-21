require 'rails_helper'

RSpec.describe Captain::Conversation::DebouncedResponseJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :open, assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:token) { 'debounce-token-1' }
  let(:redis_key) do
    format(Redis::RedisKeys::CAPTAIN_DEBOUNCE_TOKEN, conversation_id: conversation.id, assistant_id: assistant.id)
  end

  before do
    allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now)
    Redis::Alfred.set(redis_key, token)
  end

  after do
    Redis::Alfred.delete(redis_key)
  end

  context 'when the token is stale (replaced by a newer incoming message)' do
    it 'does nothing' do
      Redis::Alfred.set(redis_key, 'newer-token')

      expect do
        described_class.perform_now(conversation, assistant, token)
      end.not_to change(Captain::AssistantLog, :count)
      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end
  end

  context 'when the conversation is still owned by the assistant mirror' do
    it 'consumes the token, logs debounce_fire and fires the response builder' do
      described_class.perform_now(conversation, assistant, token)

      expect(Redis::Alfred.get(redis_key)).to be_nil
      expect(Captain::AssistantLog.where(event_type: 'debounce_fire', conversation: conversation)).to exist
      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now).with(conversation, assistant)
    end
  end

  # A3: o token Redis NÃO protege contra troca de dono (chave por conversa+assistant) —
  # o early-return por dono evita resposta e o log 'debounce_fire' falso.
  context 'when the owner changed mid-debounce' do
    it 'stays silent without logging debounce_fire when a human took over' do
      conversation.update!(assignee: create(:user, account: account, role: :agent))

      described_class.perform_now(conversation, assistant, token)

      expect(Captain::AssistantLog.where(event_type: 'debounce_fire')).not_to exist
      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end

    it 'stays silent when another assistant mirror took over' do
      other_assistant = create(:captain_assistant, account: account)
      conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)

      described_class.perform_now(conversation, assistant, token)

      expect(Captain::AssistantLog.where(event_type: 'debounce_fire')).not_to exist
      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end

    it 'stays silent when the conversation lost its owner' do
      conversation.update!(assignee_agent_bot: nil)

      described_class.perform_now(conversation, assistant, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end
  end
end
