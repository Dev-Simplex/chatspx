require 'rails_helper'

RSpec.describe Message do
  let!(:conversation) { create(:conversation) }

  it 'updates first reply if the message is human and even if there are messages from captain' do
    captain_assistant = create(:captain_assistant, account: conversation.account)
    expect(conversation.first_reply_created_at).to be_nil

    ## There is a difference on how the time is stored in the database and how it is retrieved
    # This is because of the precision of the time stored in the database
    # In the test, we will check whether the time is within the range
    expect(conversation.waiting_since).to be_within(0.000001.seconds).of(conversation.created_at)

    create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)

    # Captain::Assistant responses clear waiting_since (like AgentBot)
    expect(conversation.first_reply_created_at).to be_nil
    expect(conversation.waiting_since).to be_nil

    create(:message, message_type: :outgoing, conversation: conversation)

    expect(conversation.first_reply_created_at).not_to be_nil
    expect(conversation.waiting_since).to be_nil
  end

  describe '#mark_pending_conversation_as_open_for_human_response' do
    let(:inbox) { create(:inbox, pending_status_enabled: true) }
    let(:conversation) { create(:conversation, inbox: inbox, account: inbox.account, status: :pending) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:auto_open_activity_content) { I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale) }

    before do
      create(:captain_inbox, inbox: conversation.inbox, captain_assistant: captain_assistant)
    end

    it 'marks the conversation open when a human sends a public outgoing message' do
      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload.open?).to be true
    end

    it 'creates an activity message when a human sends a public outgoing message' do
      expect do
        create(:message, message_type: :outgoing, conversation: conversation)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'creates an activity message for external echo replies' do
      message = build(
        :message,
        message_type: :outgoing,
        conversation: conversation,
        content_attributes: { external_echo: true }
      )
      message.sender = nil

      expect do
        message.save!
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: auto_open_activity_content
        }
      )
    end

    it 'does not mark the conversation open for private outgoing messages' do
      create(:message, message_type: :outgoing, conversation: conversation, private: true)

      expect(conversation.reload.pending?).to be true
    end

    it 'does not mark the conversation open for bot outgoing messages' do
      agent_bot = create(:agent_bot, account: conversation.account)
      create(:message, message_type: :outgoing, conversation: conversation, sender: agent_bot)

      expect(conversation.reload.pending?).to be true
    end
  end

  describe '#release_captain_mirror_after_human_reply (A2c)' do
    let(:conversation) { create(:conversation) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:mirror) { captain_assistant.mirror_agent_bot }

    before do
      conversation.update!(assignee_agent_bot: mirror)
    end

    it 'releases the mirror when a human sends a public outgoing message without assigning themselves' do
      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end

    it 'releases the mirror for native echo replies (external_echo)' do
      message = build(
        :message,
        message_type: :outgoing,
        conversation: conversation,
        content_attributes: { external_echo: true }
      )
      message.sender = nil
      message.save!

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end

    it 'does not release the mirror for automation messages' do
      create(:message, message_type: :outgoing, conversation: conversation, content_attributes: { automation_rule_id: 1 })

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'does not release the mirror for campaign messages' do
      create(:message, message_type: :outgoing, conversation: conversation, additional_attributes: { campaign_id: 1 })

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'does not release the mirror for private notes' do
      create(:message, message_type: :outgoing, conversation: conversation, private: true)

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'does not release the mirror for template bootstrap messages' do
      create(
        :message,
        message_type: :outgoing,
        conversation: conversation,
        additional_attributes: { template_params: { name: 'sample_template' } }
      )

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'does not release the mirror when the assistant itself replies' do
      create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'does not release a webhook agent bot owner' do
      webhook_bot = create(:agent_bot, account: conversation.account)
      conversation.update!(assignee_agent_bot: webhook_bot)

      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload.assignee_agent_bot_id).to eq(webhook_bot.id)
    end

    it 'does not release the mirror for incoming messages' do
      create(:message, message_type: :incoming, conversation: conversation)

      expect(conversation.reload.assignee_agent_bot_id).to eq(mirror.id)
    end
  end

  # Guarda B da fila "Aguardando encerramento": o marcador cai quando o CLIENTE volta a falar.
  # O sinal é a mensagem incoming — NÃO a transição de `waiting_since`, que satura (o campo só
  # é populado quando está vazio) e cujo update sequer acontece no segundo incoming seguido.
  describe 'fila de encerramento — cliente que volta a falar' do
    let(:conversation) { create(:conversation) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }
    let(:desde) { 2.days.ago.iso8601 }

    before do
      conversation.update!(custom_attributes: { 'aguardando_encerramento_desde' => desde })
    end

    # O caso das conversas presas: a conversa entrou na fila com `waiting_since` JÁ preenchido
    # (o cliente falou por último e a IA não respondeu). O incoming novo não gera transição.
    it 'limpa o marcador quando o cliente fala e waiting_since já estava preenchido' do
      expect(conversation.reload.waiting_since).to be_present

      create(:message, message_type: :incoming, conversation: conversation)

      expect(conversation.reload.custom_attributes).not_to have_key('aguardando_encerramento_desde')
    end

    it 'limpa o marcador quando o cliente fala depois de a IA ter respondido (waiting_since nil)' do
      create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)
      expect(conversation.reload.waiting_since).to be_nil

      create(:message, message_type: :incoming, conversation: conversation)

      expect(conversation.reload.custom_attributes).not_to have_key('aguardando_encerramento_desde')
    end

    it 'limpa também os marcadores do aviso de encerramento' do
      conversation.update!(custom_attributes: { 'encerramento_avisado_em' => desde, 'encerramento_classe' => 'trivial' })

      create(:message, message_type: :incoming, conversation: conversation)

      expect(conversation.reload.custom_attributes).to be_empty
    end

    it 'não limpa o marcador quando quem responde é a própria IA' do
      create(:message, message_type: :outgoing, conversation: conversation, sender: captain_assistant)

      expect(conversation.reload.custom_attributes).to have_key('aguardando_encerramento_desde')
    end

    it 'não limpa o marcador em nota privada' do
      create(:message, message_type: :incoming, conversation: conversation, private: true)

      expect(conversation.reload.custom_attributes).to have_key('aguardando_encerramento_desde')
    end
  end
end
