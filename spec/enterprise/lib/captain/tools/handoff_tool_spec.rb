require 'rails_helper'

RSpec.describe Captain::Tools::HandoffTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  describe '#description' do
    it 'returns the correct description' do
      expect(tool.description).to eq('Hand off the conversation to a human agent when unable to assist further')
    end

    it 'enumerates the account teams when present (C6)' do
      # Team downcases o nome na validação — comparar com o valor persistido
      team_a = create(:team, account: account, name: 'Vendas').reload
      team_b = create(:team, account: account, name: 'Locacao').reload
      other_account_team = create(:team, name: 'Outra Conta').reload

      description = described_class.new(assistant).description

      expect(description).to include('Hand off the conversation to a human agent when unable to assist further')
      expect(description).to include("#{team_a.id}: #{team_a.name}")
      expect(description).to include("#{team_b.id}: #{team_b.name}")
      expect(description).not_to include("#{other_account_team.id}: #{other_account_team.name}")
    end
  end

  describe '#parameters' do
    it 'returns the correct parameters' do
      expect(tool.parameters).to have_key(:reason)
      expect(tool.parameters[:reason].name).to eq(:reason)
      expect(tool.parameters[:reason].type).to eq('string')
      expect(tool.parameters[:reason].description).to eq('The reason why handoff is needed (optional)')
      expect(tool.parameters[:reason].required).to be false
    end

    it 'declares the optional team_id parameter (C6)' do
      expect(tool.parameters).to have_key(:team_id)
      expect(tool.parameters[:team_id].type).to eq('string')
      expect(tool.parameters[:team_id].required).to be false
    end
  end

  describe '#perform' do
    context 'when conversation exists' do
      context 'with reason provided' do
        it 'creates a private note with reason and hands off conversation' do
          reason = 'Customer needs specialized support'

          expect do
            result = tool.perform(tool_context, reason: reason)
            # Modelo A: a IA segura o cliente e avisa que continua atendendo até o humano assumir.
            expect(result).to include('Time humano acionado')
          end.to change(Message, :count).by(1)
        end

        it 'creates message with correct attributes' do
          reason = 'Customer needs specialized support'
          tool.perform(tool_context, reason: reason)

          created_message = Message.last
          expect(created_message.content).to eq(reason)
          expect(created_message.message_type).to eq('outgoing')
          expect(created_message.private).to be true
          expect(created_message.sender).to eq(assistant)
          expect(created_message.account).to eq(account)
          expect(created_message.inbox).to eq(inbox)
          expect(created_message.conversation).to eq(conversation)
        end

        it 'triggers bot handoff on conversation' do
          # The tool finds the conversation by ID, so we need to mock the found conversation
          found_conversation = Conversation.find(conversation.id)
          scoped_conversations = Conversation.where(account_id: assistant.account_id)
          # call_original first so unrelated internal Conversation.where calls
          # (e.g. set_team_id_from_conversation) keep working.
          allow(Conversation).to receive(:where).and_call_original
          allow(Conversation).to receive(:where).with(account_id: assistant.account_id).and_return(scoped_conversations)
          allow(scoped_conversations).to receive(:find_by).with(id: conversation.id).and_return(found_conversation)
          expect(found_conversation).to receive(:bot_handoff!)

          tool.perform(tool_context, reason: 'Test reason')
        end

        it 'creates a conversation_bot_handoff reporting event' do
          create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
          Current.executed_by = assistant

          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Customer needs specialized support')
          end

          reporting_event = ReportingEvent.find_by(conversation_id: conversation.id, name: 'conversation_bot_handoff')
          expect(reporting_event).to be_present
        ensure
          Current.reset
        end

        it 'logs tool usage with reason' do
          reason = 'Customer needs help'
          expect(tool).to receive(:log_tool_usage).with(
            'tool_handoff',
            { conversation_id: conversation.id, reason: reason }
          )

          tool.perform(tool_context, reason: reason)
        end
      end

      # Modo Clássico (reply_assignment_gate OFF) — Modelo A (Paulo 12/06): a IA NÃO solta
      # a conversa no handoff. Mantém o espelho, seta o time, e o A2b impede o round-robin
      # (espelho presente). A conversa fica "segura" pela IA até um humano PUXAR.
      context 'when the IA owns the conversation (Classic mode — Modelo A)' do
        let(:mirror) { assistant.mirror_agent_bot }
        let(:team) { create(:team, account: account, allow_auto_assign: true) }
        let(:team_user) { create(:user, account: account) }

        before do
          create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
          create(:inbox_member, inbox: inbox, user: team_user)
          create(:team_member, team: team, user: team_user)
          conversation.update!(assignee_agent_bot: mirror)
          allow(OnlineStatusTracker).to receive(:get_available_users)
            .and_return({ team_user.id.to_s => 'online' })
        end

        it 'keeps the captain mirror (does not release it)' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Customer needs a broker')
          end

          expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
        end

        it 'does not auto-assign a human (A2b: mirror present blocks round-robin)' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Customer needs a broker', team_id: team.id.to_s)
          end

          conversation.reload
          expect(conversation.team_id).to eq(team.id)
          expect(conversation.assignee).to be_nil
        end

        it 'sets the aguardando_humano_desde marker' do
          tool.perform(tool_context, reason: 'Precisa de humano')

          expect(conversation.reload.custom_attributes['aguardando_humano_desde']).to be_present
        end

        it 'sets the team in the same handoff (C6) keeping the mirror' do
          tool.perform(tool_context, reason: 'Precisa do time de vendas', team_id: team.id.to_s)

          conversation.reload
          expect(conversation.team_id).to eq(team.id)
          expect(conversation.assignee_agent_bot_id).to eq(mirror.id)
        end

        it 'ignores a team from another account (LLM pode alucinar id)' do
          other_account_team = create(:team)

          tool.perform(tool_context, team_id: other_account_team.id.to_s)

          expect(conversation.reload.team_id).to be_nil
        end
      end

      # F1.1 — Modo FILA (reply_assignment_gate ON): handoff "pull". A IA SOLTA o espelho
      # ANTES do bot_handoff!, mantém o time, e a conversa fica "open + time + sem dono +
      # sem espelho" = aguardando humano na fila do time. Round-robin NÃO empurra (pull).
      context 'when the IA owns the conversation (fila mode — F1.1)' do
        let(:mirror) { assistant.mirror_agent_bot }
        let(:team) { create(:team, account: account, allow_auto_assign: true) }
        let(:team_user) { create(:user, account: account) }

        before do
          account.update!(settings: { reply_assignment_gate: true })
          create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
          create(:inbox_member, inbox: inbox, user: team_user)
          create(:team_member, team: team, user: team_user)
          conversation.update!(assignee_agent_bot: mirror)
          allow(OnlineStatusTracker).to receive(:get_available_users)
            .and_return({ team_user.id.to_s => 'online' })
        end

        it 'releases the captain mirror before the handoff' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Customer needs a broker', team_id: team.id.to_s)
          end

          expect(conversation.reload.assignee_agent_bot_id).to be_nil
        end

        it 'keeps the team (conversation lands in the team queue)' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Precisa do time de vendas', team_id: team.id.to_s)
          end

          expect(conversation.reload.team_id).to eq(team.id)
        end

        it 'does NOT auto-assign a human (pull, not push)' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Customer needs a broker', team_id: team.id.to_s)
          end

          expect(conversation.reload.assignee).to be_nil
        end

        it 'leaves the conversation open + team + no owner + no mirror (estável, F1.3)' do
          perform_enqueued_jobs do
            tool.perform(tool_context, reason: 'Precisa de humano', team_id: team.id.to_s)
          end

          conversation.reload
          expect(conversation.status).to eq('open')
          expect(conversation.team_id).to eq(team.id)
          expect(conversation.assignee_id).to be_nil
          expect(conversation.assignee_agent_bot_id).to be_nil
        end

        it 'sets the aguardando_humano_desde marker' do
          tool.perform(tool_context, reason: 'Precisa de humano', team_id: team.id.to_s)

          expect(conversation.reload.custom_attributes['aguardando_humano_desde']).to be_present
        end
      end

      context 'without reason provided' do
        it 'hands off the conversation without creating a private note' do
          # The tool only posts a private note when a reason is given
          # (trigger_handoff guards it behind `if reason.present?`).
          expect do
            result = tool.perform(tool_context)
            expect(result).to include('Time humano acionado')
          end.not_to change(Message, :count)
        end

        it 'logs tool usage with default reason' do
          expect(tool).to receive(:log_tool_usage).with(
            'tool_handoff',
            { conversation_id: conversation.id, reason: 'Agent requested handoff' }
          )

          tool.perform(tool_context)
        end
      end

      context 'when handoff fails' do
        before do
          # Mock the conversation lookup and handoff failure
          found_conversation = Conversation.find(conversation.id)
          scoped_conversations = Conversation.where(account_id: assistant.account_id)
          # call_original first so unrelated internal Conversation.where calls
          # (e.g. set_team_id_from_conversation) keep working.
          allow(Conversation).to receive(:where).and_call_original
          allow(Conversation).to receive(:where).with(account_id: assistant.account_id).and_return(scoped_conversations)
          allow(scoped_conversations).to receive(:find_by).with(id: conversation.id).and_return(found_conversation)
          allow(found_conversation).to receive(:bot_handoff!).and_raise(StandardError, 'Handoff error')

          exception_tracker = instance_double(ChatwootExceptionTracker)
          allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)
          allow(exception_tracker).to receive(:capture_exception)
        end

        it 'returns error message' do
          result = tool.perform(tool_context, reason: 'Test')
          expect(result).to eq('Failed to handoff conversation')
        end

        it 'captures exception' do
          exception_tracker = instance_double(ChatwootExceptionTracker)
          expect(ChatwootExceptionTracker).to receive(:new).with(instance_of(StandardError)).and_return(exception_tracker)
          expect(exception_tracker).to receive(:capture_exception)

          tool.perform(tool_context, reason: 'Test')
        end
      end
    end

    context 'when conversation does not exist' do
      let(:tool_context) { Struct.new(:state).new({ conversation: { id: 999_999 } }) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end

      it 'does not create a message' do
        expect do
          tool.perform(tool_context, reason: 'Test')
        end.not_to change(Message, :count)
      end
    end

    context 'when conversation state is missing' do
      let(:tool_context) { Struct.new(:state).new({}) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end
    end

    context 'when conversation id is nil' do
      let(:tool_context) { Struct.new(:state).new({ conversation: { id: nil } }) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end
    end
  end

  describe '#active?' do
    it 'returns true for public tools' do
      expect(tool.active?).to be true
    end
  end

  describe 'out of office message after handoff' do
    context 'when outside business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed. Please leave your email.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
      end

      it 'sends out of office message after handoff' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.to change { conversation.messages.template.count }.by(1)

        ooo_message = conversation.messages.template.last
        expect(ooo_message.content).to eq('We are currently closed. Please leave your email.')
      end
    end

    context 'when within business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          open_all_day: true,
          closed_all_day: false
        )
      end

      it 'does not send out of office message after handoff' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.not_to(change { conversation.messages.template.count })
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
      end

      it 'does not send out of office message' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.not_to(change { conversation.messages.template.count })
      end
    end
  end
end
