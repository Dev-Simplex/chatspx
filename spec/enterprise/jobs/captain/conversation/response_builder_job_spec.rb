require 'rails_helper'

RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:captain_inbox_association) { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  describe '#perform' do
    let(:conversation) do
      create(:conversation, inbox: inbox, account: account, status: :pending, assignee_agent_bot: assistant.mirror_agent_bot)
    end
    let(:mock_llm_chat_service) { instance_double(Captain::Llm::AssistantChatService) }
    let(:mock_agent_runner_service) { instance_double(Captain::Assistant::AgentRunnerService) }

    before do
      create(:message, conversation: conversation, content: 'Hello', message_type: :incoming)

      allow(inbox).to receive(:captain_active?).and_return(true)
      allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(mock_llm_chat_service)
      allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'Hey, welcome to Captain Specs' })
      allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(mock_agent_runner_service)
      allow(mock_agent_runner_service).to receive(:generate_response).and_return({ 'response' => 'Hey, welcome to Captain V2' })
    end

    context 'when captain_v2 is disabled' do
      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(false)
      end

      it 'uses Captain::Llm::AssistantChatService' do
        expect(Captain::Llm::AssistantChatService).to receive(:new).with(assistant: assistant, conversation: conversation)
        expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

        described_class.perform_now(conversation, assistant)
        expect(conversation.messages.last.content).to eq('Hey, welcome to Captain Specs')
      end

      it 'generates and processes response' do
        described_class.perform_now(conversation, assistant)
        expect(conversation.messages.count).to eq(2)
        expect(conversation.messages.outgoing.count).to eq(1)
        expect(conversation.messages.last.content).to eq('Hey, welcome to Captain Specs')
      end

      it 'increments usage response' do
        described_class.perform_now(conversation, assistant)
        account.reload
        expect(account.usage_limits[:captain][:responses][:consumed]).to eq(1)
      end

      it 'does not send a response when the conversation is no longer pending/open' do
        conversation.snoozed!

        expect(mock_llm_chat_service).not_to receive(:generate_response)
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.outgoing.count })
      end
    end

    # A3: re-check de atribuição DENTRO do job — a IA só responde conversa cujo dono
    # ainda é o espelho DESTE assistant (gate por atribuição, D-6).
    context 'with assignment re-check (A3)' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(false)
      end

      it 'stays silent when the conversation was reassigned to another assistant before perform' do
        other_assistant = create(:captain_assistant, account: account)
        conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)

        expect(mock_llm_chat_service).not_to receive(:generate_response)
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.outgoing.count })
        expect(account.reload.usage_limits[:captain][:responses][:consumed]).to eq(0)
      end

      it 'stays silent when a human took over before perform' do
        conversation.update!(assignee: agent)

        expect(mock_llm_chat_service).not_to receive(:generate_response)
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.outgoing.count })
      end

      it 'stays silent when the conversation has no owner' do
        conversation.update!(assignee_agent_bot: nil)

        expect(mock_llm_chat_service).not_to receive(:generate_response)
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.outgoing.count })
      end

      it 'does not send the response when the owner changes between the LLM call and the send' do
        allow(mock_llm_chat_service).to receive(:generate_response) do
          conversation.update!(assignee: agent)
          { 'response' => 'resposta atrasada' }
        end

        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.outgoing.count })
        expect(account.reload.usage_limits[:captain][:responses][:consumed]).to eq(0)
      end

      context 'when the humanizer splits the response into chunks' do
        let(:assistant) do
          create(:captain_assistant, account: account, behavior: { 'humanizer' => { 'enabled' => true } })
        end

        before do
          allow(mock_llm_chat_service).to receive(:generate_response).and_return(
            { 'response' => "Oi!\n\nTudo bem?\n\nSegue a informação combinada.\n\nQualquer coisa me chama." }
          )
        end

        it 'sends every chunk while the assistant still owns the conversation' do
          job = described_class.new(conversation, assistant)
          allow(job).to receive(:sleep)

          job.perform_now

          expect(conversation.messages.outgoing.count).to eq(4)
          log = Captain::AssistantLog.where(event_type: 'humanizer_split').last
          expect(log.payload).to eq('chunks' => 4, 'sent' => 4)
        end

        it 'stops the burst mid-way when the owner changes after the 2nd chunk' do
          job = described_class.new(conversation, assistant)
          sleeps = 0
          allow(job).to receive(:sleep) do
            sleeps += 1
            # Humano assume durante o "digitando..." do 3º chunk -> rajada para ali.
            conversation.update!(assignee: agent) if sleeps == 3
          end

          job.perform_now

          expect(conversation.messages.outgoing.count).to eq(2)
          log = Captain::AssistantLog.where(event_type: 'humanizer_split').last
          expect(log.payload).to eq('chunks' => 4, 'sent' => 2)
        end
      end
    end

    context 'when captain_v2 is enabled' do
      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(true)
      end

      it 'uses Captain::Assistant::AgentRunnerService' do
        expect(Captain::Assistant::AgentRunnerService).to receive(:new).with(
          assistant: assistant,
          conversation: conversation
        )
        expect(Captain::Llm::AssistantChatService).not_to receive(:new)

        described_class.perform_now(conversation, assistant)
        expect(conversation.messages.last.content).to eq('Hey, welcome to Captain V2')
      end

      it 'passes message history to agent runner service' do
        expected_messages = [
          { content: 'Hello', role: 'user' }
        ]

        expect(mock_agent_runner_service).to receive(:generate_response).with(
          message_history: expected_messages
        )

        described_class.perform_now(conversation, assistant)
      end

      # BUG C: a pesquisa NPS (no WhatsApp = content_type text marcado com nps_survey) entrava
      # no historico como turno "assistant" e o LLM mimetizava, respondendo "De 0 a 10..." em
      # vez de atender. Ela nao pode ir pro contexto do LLM.
      it 'excludes NPS/CSAT survey messages from the message history' do
        create(:message, :bot_message, conversation: conversation,
                                       content_type: :text, content: 'De 0 a 10, qual a nota que voce da?',
                                       content_attributes: { nps_survey: true })

        expect(mock_agent_runner_service).to receive(:generate_response) do |**kwargs|
          contents = kwargs[:message_history].pluck(:content)
          expect(contents).to include('Hello')
          expect(contents).not_to include('De 0 a 10, qual a nota que voce da?')
          { 'response' => 'Hey, welcome to Captain V2' }
        end

        described_class.perform_now(conversation, assistant)
      end

      it 'generates and processes response' do
        described_class.perform_now(conversation, assistant)
        expect(conversation.messages.count).to eq(2)
        expect(conversation.messages.outgoing.count).to eq(1)
        expect(conversation.messages.last.content).to eq('Hey, welcome to Captain V2')
      end

      it 'increments usage response' do
        described_class.perform_now(conversation, assistant)
        account.reload
        expect(account.usage_limits[:captain][:responses][:consumed]).to eq(1)
      end

      # C7.4 (gap AD-11/B4): agent_name que não pertence ao assistant ATUAL não pode
      # rotear persona — mensagem de OUTRA IA (transferência C7) ou de cenário legado
      # entra no histórico sem agent_name (cairia no agente default da gem).
      context 'with the agent_name forwarding guard (C7.4)' do
        def history_entry(content)
          history = nil
          allow(mock_agent_runner_service).to receive(:generate_response) do |message_history:|
            history = message_history
            { 'response' => 'ok' }
          end
          described_class.perform_now(conversation, assistant)
          history.find { |entry| entry[:content] == content }
        end

        it 'does not forward agent_name from another AI' do
          create(:message, conversation: conversation, message_type: :outgoing, sender: assistant,
                           content: 'fala da outra IA', additional_attributes: { 'agent_name' => 'outra_ia_qualquer' })

          expect(history_entry('fala da outra IA')).not_to have_key(:agent_name)
        end

        it 'does not forward agent_name from a legacy/disabled scenario' do
          create(:message, conversation: conversation, message_type: :outgoing, sender: assistant,
                           content: 'cenario antigo', additional_attributes: { 'agent_name' => 'scenario_999_legado_agent' })

          expect(history_entry('cenario antigo')).not_to have_key(:agent_name)
        end

        it 'forwards the own agent_name of the current assistant' do
          own_name = assistant.name.parameterize(separator: '_')
          create(:message, conversation: conversation, message_type: :outgoing, sender: assistant,
                           content: 'fala minha', additional_attributes: { 'agent_name' => own_name })

          expect(history_entry('fala minha')[:agent_name]).to eq(own_name)
        end

        it 'forwards the handoff_key of an enabled scenario of the current assistant' do
          scenario = create(:captain_scenario, assistant: assistant, account: account)
          create(:message, conversation: conversation, message_type: :outgoing, sender: assistant,
                           content: 'fala do cenario', additional_attributes: { 'agent_name' => scenario.handoff_key })

          expect(history_entry('fala do cenario')[:agent_name]).to eq(scenario.handoff_key)
        end
      end
    end

    # Regression (PR #13417): wrapping create_handoff_message and bot_handoff! in the
    # same transaction defers the message's after_create_commit until commit, at which
    # point it clears waiting_since (bot_response). The handoff path must stay outside
    # the transaction so the callback fires before bot_handoff! sets waiting_since.
    context 'when handoff is requested' do
      let(:conversation) do
        create(:conversation, inbox: inbox, account: account, status: :pending, assignee_agent_bot: assistant.mirror_agent_bot)
      end
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(false)
        allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff' })
      end

      it 'sets waiting_since to approximately the handoff time' do
        freeze_time do
          described_class.perform_now(conversation, assistant)

          conversation.reload
          expect(conversation.status).to eq('open')
          expect(conversation.waiting_since).to be_within(1.second).of(Time.current)
        end
      end

      it 'preserves waiting_since so a human reply consumes it for reply_time tracking' do
        described_class.perform_now(conversation, assistant)

        conversation.reload
        expect(conversation.waiting_since).to be_present

        # A human reply clears waiting_since (consumed by dispatch_create_events
        # to emit FIRST_REPLY_CREATED or REPLY_CREATED for reply_time tracking).
        create(:message, conversation: conversation, message_type: :outgoing,
                         sender: agent, account: account, inbox: inbox)
        expect(conversation.reload.waiting_since).to be_nil
      end
    end

    context 'when message contains an image' do
      let(:message_with_image) { create(:message, conversation: conversation, message_type: :incoming, content: 'Can you help with this error?') }
      let(:image_attachment) { message_with_image.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/error.jpg') }

      before do
        image_attachment
      end

      it 'includes image URL directly in the message content for OpenAI vision analysis' do
        # Expect the generate_response to receive multimodal content with image URL
        expect(mock_llm_chat_service).to receive(:generate_response) do |**kwargs|
          history = kwargs[:message_history]
          last_entry = history.last
          expect(last_entry[:content]).to be_an(Array)
          expect(last_entry[:content].any? { |part| part[:type] == 'text' && part[:text] == 'Can you help with this error?' }).to be true
          expect(last_entry[:content].any? do |part|
            part[:type] == 'image_url' && part[:image_url][:url] == 'https://example.com/error.jpg'
          end).to be true
          { 'response' => 'I can see the error in your image. It appears to be a database connection issue.' }
        end

        described_class.perform_now(conversation, assistant)
      end
    end
  end

  describe 'retry mechanisms for image processing' do
    let(:conversation) do
      create(:conversation, inbox: inbox, account: account, status: :pending, assignee_agent_bot: assistant.mirror_agent_bot)
    end
    let(:mock_llm_chat_service) { instance_double(Captain::Llm::AssistantChatService) }
    let(:mock_message_builder) { instance_double(Captain::OpenAiMessageBuilderService) }

    before do
      create(:message, conversation: conversation, content: 'Hello with image', message_type: :incoming)
      allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(mock_llm_chat_service)
      allow(Captain::OpenAiMessageBuilderService).to receive(:new).with(message: anything).and_return(mock_message_builder)
      allow(mock_message_builder).to receive(:generate_content).and_return('Hello with image')
      allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'Test response' })
    end

    context 'when ActiveStorage::FileNotFoundError occurs' do
      it 'handles file errors and triggers handoff' do
        allow(mock_message_builder).to receive(:generate_content)
          .and_raise(ActiveStorage::FileNotFoundError, 'Image file not found')

        # For retryable errors, the job should handle them and proceed with handoff
        described_class.perform_now(conversation, assistant)

        # Verify handoff occurred due to repeated failures
        expect(conversation.reload.status).to eq('open')
      end

      it 'succeeds when no error occurs' do
        # Don't raise any error, should succeed normally
        allow(mock_message_builder).to receive(:generate_content)
          .and_return('Image content processed successfully')

        described_class.perform_now(conversation, assistant)

        expect(conversation.messages.outgoing.count).to eq(1)
        expect(conversation.messages.outgoing.last.content).to eq('Test response')
      end
    end

    context 'when Faraday::BadRequestError occurs' do
      it 'handles API errors and triggers handoff' do
        allow(mock_llm_chat_service).to receive(:generate_response)
          .and_raise(Faraday::BadRequestError, 'Bad request to image service')

        described_class.perform_now(conversation, assistant)
        expect(conversation.reload.status).to eq('open')
      end

      it 'succeeds when no error occurs' do
        # Don't raise any error, should succeed normally
        allow(mock_llm_chat_service).to receive(:generate_response)
          .and_return({ 'response' => 'Response after retry' })

        described_class.perform_now(conversation, assistant)

        expect(conversation.messages.outgoing.last.content).to eq('Response after retry')
      end
    end

    context 'when image processing fails permanently' do
      before do
        allow(mock_message_builder).to receive(:generate_content)
          .and_raise(ActiveStorage::FileNotFoundError, 'Image permanently unavailable')
      end

      it 'triggers handoff after max retries' do
        # Since perform_now re-raises retryable errors, simulate the final failure after retries
        allow(mock_message_builder).to receive(:generate_content)
          .and_raise(StandardError, 'Max retries exceeded')

        expect(ChatwootExceptionTracker).to receive(:new).and_call_original

        described_class.perform_now(conversation, assistant)

        expect(conversation.reload.status).to eq('open')
      end
    end

    context 'when non-retryable error occurs' do
      let(:standard_error) { StandardError.new('Generic error') }

      before do
        allow(mock_llm_chat_service).to receive(:generate_response).and_raise(standard_error)
      end

      it 'handles error and triggers handoff' do
        expect(ChatwootExceptionTracker).to receive(:new)
          .with(standard_error, account: account)
          .and_call_original

        described_class.perform_now(conversation, assistant)

        expect(conversation.reload.status).to eq('open')
      end

      it 'ensures Current.executed_by is reset' do
        expect(Current).to receive(:executed_by=).with(assistant)
        expect(Current).to receive(:executed_by=).with(nil)

        described_class.perform_now(conversation, assistant)
      end
    end
  end

  describe 'job configuration' do
    it 'has retry_on configuration for retryable errors' do
      expect(described_class).to respond_to(:retry_on)
    end

    it 'defines MAX_MESSAGE_LENGTH constant' do
      expect(described_class::MAX_MESSAGE_LENGTH).to eq(10_000)
    end
  end

  describe 'out of office message after handoff' do
    let(:conversation) do
      create(:conversation, inbox: inbox, account: account, status: :pending, assignee_agent_bot: assistant.mirror_agent_bot)
    end
    let(:mock_llm_chat_service) { instance_double(Captain::Llm::AssistantChatService) }

    before do
      create(:message, conversation: conversation, content: 'Hello', message_type: :incoming)
      allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(mock_llm_chat_service)
      allow(account).to receive(:feature_enabled?).and_return(false)
      allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(false)
    end

    context 'when handoff occurs outside business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed. Please leave your email.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
        allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff' })
      end

      it 'sends out of office message after handoff' do
        expect do
          described_class.perform_now(conversation, assistant)
        end.to change { conversation.messages.template.count }.by(1)

        expect(conversation.reload.status).to eq('open')
        ooo_message = conversation.messages.template.last
        expect(ooo_message.content).to eq('We are currently closed. Please leave your email.')
      end
    end

    context 'when handoff occurs within business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          open_all_day: true,
          closed_all_day: false
        )
        allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff' })
      end

      it 'does not send out of office message after handoff' do
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.template.count })

        expect(conversation.reload.status).to eq('open')
      end
    end

    context 'when handoff occurs due to error outside business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
        allow(mock_llm_chat_service).to receive(:generate_response).and_raise(StandardError, 'API error')
      end

      it 'sends out of office message after error-triggered handoff' do
        expect do
          described_class.perform_now(conversation, assistant)
        end.to change { conversation.messages.template.count }.by(1)

        expect(conversation.reload.status).to eq('open')
        ooo_message = conversation.messages.template.last
        expect(ooo_message.content).to eq('We are currently closed.')
      end
    end

    context 'when no out of office message is configured' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: nil
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
        allow(mock_llm_chat_service).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff' })
      end

      it 'does not send out of office message' do
        expect do
          described_class.perform_now(conversation, assistant)
        end.not_to(change { conversation.messages.template.count })
      end
    end
  end
end
