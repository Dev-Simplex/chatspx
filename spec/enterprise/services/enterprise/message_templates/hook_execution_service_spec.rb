require 'rails_helper'

RSpec.describe MessageTemplates::HookExecutionService do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:mirror) { assistant.mirror_agent_bot }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
  end

  describe 'gate por atribuição (D-6)' do
    it 'does not schedule a response nor log anything when the conversation has no owner (eligible inbox)' do
      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.not_to change(Captain::AssistantLog, :count)
    end

    it 'schedules the response with the assistant whose mirror owns the conversation' do
      conversation.update!(assignee_agent_bot: mirror)

      expect(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later).with(conversation, assistant)

      create(:message, conversation: conversation, message_type: :incoming, account: account)
    end

    it 'schedules the response with the second assistant when its mirror owns the conversation' do
      other_assistant = create(:captain_assistant, account: account)
      conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)

      expect(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later).with(conversation, other_assistant)

      create(:message, conversation: conversation, message_type: :incoming, account: account)
    end

    it 'stays silent when the conversation is assigned to a human' do
      agent = create(:user, account: account, role: :agent)
      conversation.update!(assignee: agent)

      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.not_to change(Captain::AssistantLog, :count)
    end

    it 'stays silent when the conversation is assigned to a webhook agent bot' do
      webhook_bot = create(:agent_bot, account: account)
      conversation.update!(assignee_agent_bot: webhook_bot)

      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.not_to change(Captain::AssistantLog, :count)
    end

    it 'no longer blocks on the atendimento_humano custom attribute (trava morta)' do
      conversation.update!(assignee_agent_bot: mirror, custom_attributes: { 'atendimento_humano' => true })

      expect(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later).with(conversation, assistant)

      create(:message, conversation: conversation, message_type: :incoming, account: account)
    end

    it 'still responds on pending conversations owned by the mirror (legado)' do
      inbox.update!(pending_status_enabled: true)
      pending_conversation = create(:conversation, inbox: inbox, account: account, contact: contact, status: :pending)
      pending_conversation.update!(assignee_agent_bot: mirror)

      expect(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later).with(pending_conversation, assistant)

      create(:message, conversation: pending_conversation, message_type: :incoming, account: account)
    end

    it 'does not schedule a response for outgoing messages' do
      conversation.update!(assignee_agent_bot: mirror)

      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      create(:message, conversation: conversation, message_type: :outgoing, account: account)
    end
  end

  describe 'debounce' do
    it 'routes through DebounceService with the assigned assistant when debounce_seconds is positive' do
      assistant.update!(behavior: { 'debounce_seconds' => 10 })
      conversation.update!(assignee_agent_bot: mirror)

      debounce_service = instance_double(Captain::Behavior::DebounceService, schedule: true)
      allow(Captain::Behavior::DebounceService).to receive(:new).with(assistant: assistant, conversation: conversation)
                                                                .and_return(debounce_service)
      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      create(:message, conversation: conversation, message_type: :incoming, account: account)

      expect(debounce_service).to have_received(:schedule)
    end
  end

  describe 'copilot trigger (re-keyado pela atribuição)' do
    let(:chat_service) { instance_double(Captain::Copilot::ChatService, generate_response: true) }

    before do
      assistant.update!(behavior: { 'copilot_trigger' => { 'enabled' => true } })
      allow(Captain::Copilot::ChatService).to receive(:new).and_return(chat_service)
    end

    it 'triggers copilot for private messages on conversations owned by the mirror' do
      conversation.update!(assignee_agent_bot: mirror)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, private: true,
                         content: 'help me #copilot', account: account)
      end.to change { Captain::AssistantLog.where(event_type: 'copilot_trigger').count }.by(1)
    end

    it 'does not trigger copilot when the conversation has no owner' do
      expect do
        create(:message, conversation: conversation, message_type: :incoming, private: true,
                         content: 'help me #copilot', account: account)
      end.not_to change(Captain::AssistantLog, :count)
    end
  end

  describe 'greeting/OOO/email collect suppression by eligibility' do
    it 'does not create greeting message on eligible inbox even without assignment' do
      inbox.update!(greeting_enabled: true, greeting_message: 'Hello! How can we help you?', enable_email_collect: false)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.not_to(change { conversation.reload.messages.template.count })
    end

    it 'does not create out of office message on eligible inbox even without assignment' do
      inbox.update!(
        working_hours_enabled: true,
        out_of_office_message: 'We are currently closed',
        enable_email_collect: false
      )
      inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
        closed_all_day: true,
        open_all_day: false
      )

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.not_to(change { conversation.reload.messages.template.count })
    end

    it 'does not send email collect on eligible inbox even without assignment' do
      contact.update!(email: nil)
      inbox.update!(enable_email_collect: true)

      email_collect_service = instance_double(MessageTemplates::Template::EmailCollect)
      allow(MessageTemplates::Template::EmailCollect).to receive(:new).and_return(email_collect_service)
      allow(email_collect_service).to receive(:perform).and_return(true)

      create(:message, conversation: conversation, message_type: :incoming, account: account)

      expect(MessageTemplates::Template::EmailCollect).not_to have_received(:new)
    end
  end

  context 'when inbox is not eligible (no CaptainInbox)' do
    before do
      CaptainInbox.where(inbox: inbox).destroy_all
    end

    it 'does not schedule captain response job' do
      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      create(:message, conversation: conversation, message_type: :incoming, account: account)
    end

    it 'creates greeting message in conversation' do
      inbox.update!(greeting_enabled: true, greeting_message: 'Hello! How can we help you?', enable_email_collect: false)

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.to change { conversation.reload.messages.template.count }.by(1)

      greeting_message = conversation.reload.messages.template.last
      expect(greeting_message.content).to eq('Hello! How can we help you?')
    end

    it 'creates out of office message when outside business hours' do
      inbox.update!(
        working_hours_enabled: true,
        out_of_office_message: 'We are currently closed',
        enable_email_collect: false
      )
      inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
        closed_all_day: true,
        open_all_day: false
      )

      expect do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
      end.to change { conversation.reload.messages.template.count }.by(1)

      out_of_office_message = conversation.reload.messages.template.last
      expect(out_of_office_message.content).to eq('We are currently closed')
    end
  end

  describe 'perform_handoff (A8 — cota zerada, re-keyado pra atribuição)' do
    before do
      account.update!(
        locale: 'pt_BR',
        limits: { 'captain_responses' => 100 },
        custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 100)
      )
    end

    context 'when the conversation is owned by the mirror' do
      before do
        conversation.update!(assignee_agent_bot: mirror)
      end

      it 'sends the handoff message in the account locale with the assistant as sender' do
        create(:message, conversation: conversation, message_type: :incoming, account: account)

        handoff_message = conversation.reload.messages.outgoing.last
        expect(handoff_message.content).to eq('Transferindo para que outro agente dê assistência.')
        expect(handoff_message.sender).to eq(assistant)
      end

      it 'unassigns the mirror and dispatches bot_handoff' do
        create(:message, conversation: conversation, message_type: :incoming, account: account)

        expect(conversation.reload.assignee_agent_bot_id).to be_nil
        expect(conversation.reload.status).to eq('open')
      end

      it 'does not repeat the handoff message on subsequent incoming messages (anti-spam)' do
        create(:message, conversation: conversation, message_type: :incoming, account: account)

        expect do
          create(:message, conversation: conversation.reload, message_type: :incoming, account: account)
        end.not_to(change { conversation.reload.messages.outgoing.count })
      end

      it 'honors the assistant custom handoff_message' do
        assistant.update!(config: { 'handoff_message' => 'Vou te passar pro nosso time humano.' })

        create(:message, conversation: conversation, message_type: :incoming, account: account)

        expect(conversation.reload.messages.outgoing.last.content).to eq('Vou te passar pro nosso time humano.')
      end
    end

    context 'when the conversation has no owner' do
      it 'is a no-op (no message, no handoff)' do
        expect do
          create(:message, conversation: conversation, message_type: :incoming, account: account)
        end.not_to(change { conversation.reload.messages.outgoing.count })
      end
    end

    context 'when the conversation is owned by a human' do
      it 'is a no-op (no message, no handoff)' do
        agent = create(:user, account: account, role: :agent)
        conversation.update!(assignee: agent)

        expect do
          create(:message, conversation: conversation, message_type: :incoming, account: account)
        end.not_to(change { conversation.reload.messages.outgoing.count })
      end
    end

    context 'when outside business hours' do
      before do
        conversation.update!(assignee_agent_bot: mirror)
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed. Please leave your email.',
          enable_email_collect: false
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
      end

      it 'sends out of office message after handoff due to quota exceeded' do
        expect do
          create(:message, conversation: conversation, message_type: :incoming, account: account)
        end.to change { conversation.messages.template.count }.by(1)

        expect(conversation.reload.status).to eq('open')
        ooo_message = conversation.messages.template.last
        expect(ooo_message.content).to eq('We are currently closed. Please leave your email.')
      end
    end

    context 'when within business hours' do
      before do
        conversation.update!(assignee_agent_bot: mirror)
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed.',
          enable_email_collect: false
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          open_all_day: true,
          closed_all_day: false
        )
      end

      it 'does not send out of office message after handoff' do
        expect do
          create(:message, conversation: conversation, message_type: :incoming, account: account)
        end.not_to(change { conversation.messages.template.count })

        expect(conversation.reload.status).to eq('open')
      end
    end
  end

  context 'when conversation has a campaign' do
    let(:campaign) { create(:campaign, account: account) }
    let(:campaign_conversation) { create(:conversation, inbox: inbox, account: account, contact: contact, campaign: campaign) }

    it 'schedules captain response job for incoming messages when the mirror owns the conversation' do
      campaign_conversation.update!(assignee_agent_bot: mirror)

      expect(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later).with(campaign_conversation, assistant)

      create(:message, conversation: campaign_conversation, message_type: :incoming, account: account)
    end

    it 'does not send greeting template on campaign conversations' do
      inbox.update!(greeting_enabled: true, greeting_message: 'Hello! How can we help you?', enable_email_collect: false)

      greeting_service = instance_double(MessageTemplates::Template::Greeting)
      allow(MessageTemplates::Template::Greeting).to receive(:new).and_return(greeting_service)
      allow(greeting_service).to receive(:perform).and_return(true)

      create(:message, conversation: campaign_conversation, message_type: :incoming, account: account)

      expect(MessageTemplates::Template::Greeting).not_to have_received(:new)
    end

    it 'does not send out of office template after handoff on campaign conversations when quota is exceeded' do
      campaign_conversation.update!(assignee_agent_bot: mirror)
      account.update!(
        limits: { 'captain_responses' => 100 },
        custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 100)
      )
      inbox.update!(
        working_hours_enabled: true,
        out_of_office_message: 'We are currently closed'
      )
      inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
        closed_all_day: true,
        open_all_day: false
      )

      expect do
        create(:message, conversation: campaign_conversation, message_type: :incoming, account: account)
      end.not_to(change { campaign_conversation.messages.template.count })
    end
  end

  # F1.2 🔴 — gate da re-captura automática (orphan_captain_reentry?).
  # Cenário comum aos dois modos: conversa SOLTA (open + team + sem dono + sem espelho)
  # com a IA do setor elegível, e chega uma mensagem do cliente.
  describe 'orphan captain reentry gate (F1.2)' do
    let(:team) { create(:team, account: account) }
    let(:orphan_conversation) do
      create(:conversation, inbox: inbox, account: account, contact: contact,
                            status: :open, team: team, assignee: nil)
    end

    before do
      # A IA do setor: assistant cujo config['team_id'] aponta pro time da conversa, elegível na inbox.
      assistant.update!(config: { 'team_id' => team.id })
      orphan_conversation # materializa antes de mexer no espelho
    end

    context 'when in classic mode (reply_assignment_gate OFF)' do
      # O exemplo dizia "IA do setor reentra" e e de 21/06. Em 29/06 a regra MUDOU (555ebd36b3,
      # "reentrada de conversa reaberta volta pra triagem (Clara) com time limpo, EM VEZ do
      # especialista do ultimo time"): `reattach_triage_assistant` procura o assistente de TRIAGEM
      # (`config['triage'] == true`) e LIMPA o time, porque o cliente pode ter voltado por outro
      # assunto e quem reavalia e a triagem.
      #
      # Sem assistente de triagem no arranjo, `triage_assistant` era nil e o portao nem abria —
      # o exemplo acusava "nao reatou" por falta de sujeito, nao por defeito.
      let!(:triagem) do
        create(:captain_assistant, account: account, config: { 'triage' => true }).tap do |a|
          create(:captain_inbox, captain_assistant: a, inbox: inbox)
        end
      end

      it 'reattaches the TRIAGE assistant and clears the team (555ebd36b3)' do
        expect do
          create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)
        end.to change { orphan_conversation.reload.assignee_agent_bot_id }.from(nil).to(triagem.mirror_agent_bot.id)

        expect(orphan_conversation.reload.team_id).to be_nil
      end
    end

    context 'when in fila mode (reply_assignment_gate ON)' do
      before { account.update!(settings: { reply_assignment_gate: true }) }

      it 'does NOT reattach the sector assistant — conversation stays awaiting human' do
        expect do
          create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)
        end.not_to(change { orphan_conversation.reload.assignee_agent_bot_id })

        expect(orphan_conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'leaves the conversation open + team + no owner + no mirror (estável, F1.3)' do
        create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)

        orphan_conversation.reload
        expect(orphan_conversation.status).to eq('open')
        expect(orphan_conversation.team_id).to eq(team.id)
        expect(orphan_conversation.assignee_id).to be_nil
        expect(orphan_conversation.assignee_agent_bot_id).to be_nil
      end

      it 'does not schedule a captain response (no owner to process)' do
        expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

        create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)
      end
    end

    # A conta que abandonou a fila quer a exigência de atribuição para o humano responder E a
    # reentrada da IA — as duas vinham na MESMA chave, então era tudo ou nada. Aqui a conta
    # segue em modo fila (o humano continua obrigado a se atribuir) e a órfã volta a ter dono.
    context 'when the account opted into ia_reentra_orfa while still in fila mode' do
      before { account.update!(settings: { reply_assignment_gate: true, ia_reentra_orfa: true }) }

      it 'reattaches the sector assistant, so the conversation has an owner again' do
        expect do
          create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)
        end.to change { orphan_conversation.reload.assignee_agent_bot_id }.from(nil).to(assistant.mirror_agent_bot.id)
      end

      # A exigência de atribuição para o humano responder é a OUTRA metade da flag e não pode
      # cair junto: é o que impede alguém responder uma conversa que não é sua.
      it 'keeps the reply assignment gate on' do
        expect(account.reload.reply_assignment_gate_enabled?).to be(true)
      end
    end

    # Desligar explicitamente vale mesmo fora do modo fila — a conta escolhe, não deduz.
    context 'when the account opted OUT of ia_reentra_orfa in classic mode' do
      before { account.update!(settings: { reply_assignment_gate: false, ia_reentra_orfa: false }) }

      it 'does not reattach the sector assistant' do
        expect do
          create(:message, conversation: orphan_conversation, message_type: :incoming, account: account)
        end.not_to(change { orphan_conversation.reload.assignee_agent_bot_id })
      end
    end
  end

  describe 'integração A2c × gate (sucessor do skip_after_human_response)' do
    it 'stays silent after a human replies without assigning themselves (mirror released by A2c)' do
      conversation.update!(assignee_agent_bot: mirror)
      assistant.update!(behavior: { 'router' => { 'skip_after_human_response' => true } })

      create(:message, conversation: conversation, message_type: :outgoing, account: account)

      expect(conversation.reload.assignee_agent_bot_id).to be_nil

      expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)

      create(:message, conversation: conversation, message_type: :incoming, account: account)
    end
  end
end
