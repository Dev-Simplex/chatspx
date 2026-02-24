require 'rails_helper'

RSpec.describe Captain::Copilot::ResponseJob, type: :job do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
  let(:conversation_id) { 123 }
  let(:message) { 'Test message' }
  let(:trigger_message) do
    create(
      :captain_copilot_message,
      copilot_thread: copilot_thread,
      account: account,
      message_type: :user,
      message: { content: message }
    )
  end

  describe '#perform' do
    let(:chat_service) { instance_double(Captain::Copilot::ChatService) }

    before do
      allow(Captain::Copilot::ChatService).to receive(:new).with(
        assistant,
        user_id: user.id,
        copilot_thread_id: copilot_thread.id,
        conversation_id: conversation_id
      ).and_return(chat_service)
      # When copilot_thread_id is present, message is already in previous_history
      # so nil is passed to avoid duplicate
      allow(chat_service).to receive(:generate_response).with(nil)
    end

    it 'uses high queue priority' do
      expect(described_class.queue_name).to eq('high')
    end

    it 'initializes ChatService with correct parameters and calls generate_response' do
      expect(Captain::Copilot::ChatService).to receive(:new).with(
        assistant,
        user_id: user.id,
        copilot_thread_id: copilot_thread.id,
        conversation_id: conversation_id
      )
      # Message is already persisted in copilot_thread.previous_history,
      # so we pass nil to prevent duplicate user messages
      expect(chat_service).to receive(:generate_response).with(nil)
      described_class.perform_now(
        assistant: assistant,
        conversation_id: conversation_id,
        user_id: user.id,
        copilot_thread_id: copilot_thread.id,
        copilot_message_id: trigger_message.id,
        message: message
      )
    end

    it 'creates timeout fallback assistant message when request exceeds timeout' do
      allow(chat_service).to receive(:generate_response).with(nil).and_raise(Timeout::Error)

      expect do
        described_class.perform_now(
          assistant: assistant,
          conversation_id: conversation_id,
          user_id: user.id,
          copilot_thread_id: copilot_thread.id,
          copilot_message_id: trigger_message.id,
          message: message
        )
      end.to change { copilot_thread.copilot_messages.assistant.count }.by(1)

      expect(copilot_thread.copilot_messages.assistant.last.message['content']).to eq(
        I18n.t('captain.copilot.timeout')
      )
    end

    it 'creates generic fallback assistant message when request fails' do
      allow(chat_service).to receive(:generate_response).with(nil).and_raise(StandardError.new('boom'))

      expect do
        described_class.perform_now(
          assistant: assistant,
          conversation_id: conversation_id,
          user_id: user.id,
          copilot_thread_id: copilot_thread.id,
          copilot_message_id: trigger_message.id,
          message: message
        )
      end.to change { copilot_thread.copilot_messages.assistant.count }.by(1)

      expect(copilot_thread.copilot_messages.assistant.last.message['content']).to eq(
        I18n.t('captain.copilot.failure')
      )
    end

    it 'creates missing key fallback assistant message when account key is absent' do
      allow(chat_service)
        .to receive(:generate_response)
        .with(nil)
        .and_raise(Llm::Config::MissingAccountApiKeyError.new('missing key'))

      expect do
        described_class.perform_now(
          assistant: assistant,
          conversation_id: conversation_id,
          user_id: user.id,
          copilot_thread_id: copilot_thread.id,
          copilot_message_id: trigger_message.id,
          message: message
        )
      end.to change { copilot_thread.copilot_messages.assistant.count }.by(1)

      expect(copilot_thread.copilot_messages.assistant.last.message['content']).to eq(
        I18n.t('captain.errors.missing_api_key')
      )
    end

    it 'does not create duplicate fallback when assistant message already exists after trigger message' do
      trigger_message
      create(
        :captain_copilot_message,
        copilot_thread: copilot_thread,
        account: account,
        message_type: :assistant,
        message: { content: 'already answered' }
      )

      allow(chat_service).to receive(:generate_response).with(nil).and_raise(Timeout::Error)

      expect do
        described_class.perform_now(
          assistant: assistant,
          conversation_id: conversation_id,
          user_id: user.id,
          copilot_thread_id: copilot_thread.id,
          copilot_message_id: trigger_message.id,
          message: message
        )
      end.not_to change(CopilotMessage, :count)
    end
  end
end
