require 'rails_helper'

RSpec.describe Captain::Conversation::AssignmentKickJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :open,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end

  let(:hook_service) { instance_double(MessageTemplates::HookExecutionService, perform: nil) }

  def add_incoming
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: 'oi, preciso de ajuda')
  end

  def add_outgoing(sender: nil)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, sender: sender, content: 'ja respondi')
  end

  # Criar mensagens já invoca o HookExecutionService (message.rb:351). Só queremos medir
  # o que o JOB faz, então (re)instalamos o stub APÓS montar o cenário — isso zera o
  # histórico de chamadas do pipeline de criação.
  def stub_hook!
    allow(MessageTemplates::HookExecutionService).to receive(:new).and_return(hook_service)
  end

  context 'when the last visible message is an unanswered incoming' do
    it 'replays the pipeline through the hook with that message' do
      incoming = add_incoming
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).to have_received(:new).with(message: incoming)
      expect(hook_service).to have_received(:perform)
    end
  end

  context 'when the last visible message is outgoing (already answered)' do
    it 'is a no-op (someone — human or AI — already replied)' do
      add_incoming
      add_outgoing(sender: create(:user, account: account, role: :agent))
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end

    it 'is a no-op when the assistant itself already answered' do
      add_incoming
      add_outgoing(sender: assistant)
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end
  end

  context 'when the conversation has no pending incoming' do
    it 'is a no-op when there are no messages at all' do
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end

    it 'ignores private messages when deciding the last visible message' do
      add_outgoing(sender: create(:user, account: account, role: :agent))
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: 'nota interna',
                       sender: create(:user, account: account, role: :agent))
      stub_hook!

      described_class.perform_now(conversation)

      # último visível é o outgoing público -> já respondida.
      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end
  end

  context 'when the owner changed between the callback and the job' do
    it 'is a no-op when a human took over' do
      add_incoming
      conversation.update!(assignee: create(:user, account: account, role: :agent),
                           assignee_agent_bot: nil)
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end

    it 'is a no-op when the conversation lost its owner' do
      add_incoming
      conversation.update!(assignee_agent_bot: nil)
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end

    it 'still kicks when another assistant mirror took over (IA->IA)' do
      add_incoming
      other = create(:captain_assistant, account: account)
      conversation.update!(assignee_agent_bot: other.mirror_agent_bot)
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).to have_received(:new)
    end
  end

  context 'when the conversation is resolved' do
    it 'is a no-op (status guard)' do
      add_incoming
      # resolve limpa o espelho (A2e); pula a validação para isolar o guard de status.
      conversation.update_columns(status: Conversation.statuses[:resolved]) # rubocop:disable Rails/SkipsModelValidations
      stub_hook!

      described_class.perform_now(conversation)

      expect(MessageTemplates::HookExecutionService).not_to have_received(:new)
    end
  end
end
