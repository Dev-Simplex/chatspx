require 'rails_helper'

RSpec.describe Captain::Behavior::RouterService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5565999111222') }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:message) { build(:message, conversation: conversation, message_type: :incoming, account: account) }

  def should_respond?(msg = message)
    described_class.new(assistant: assistant, conversation: conversation, message: msg).should_respond?
  end

  # Menção não é mensagem: é notificação que o Instagram entrega em forma de mensagem, e o
  # texto é gerado por nós. Medido na Tozi (inbox 101), 60 dias: 53 dessas viraram 48 respostas
  # da IA, várias perguntando a corretores da própria casa se queriam alugar ou comprar.
  describe 'menção da marca no story de outra pessoa' do
    def com_tipo(tipo)
      build(:message, conversation: conversation, message_type: :incoming, account: account,
                      content: 'fulano mencionou você na conversa:', content_attributes: { 'image_type' => tipo })
    end

    it 'does not respond to a story mention' do
      expect(should_respond?(com_tipo('story_mention'))).to be false
    end

    # As três abaixo são conversa de verdade: em todas a pessoa mandou algo para nós de
    # propósito. Se caírem no mesmo balde, a IA fica muda com quem respondeu ao story da marca
    # — que é justamente o lead que este canal produz.
    it 'still responds to a reply to our own story' do
      expect(should_respond?(com_tipo('ig_story_reply'))).to be true
    end

    it 'still responds to a story shared into the direct' do
      expect(should_respond?(com_tipo('ig_story'))).to be true
    end

    it 'still responds to a post shared into the direct' do
      expect(should_respond?(com_tipo('ig_post'))).to be true
    end

    it 'is inert on channels that have no image_type at all' do
      expect(should_respond?).to be true
    end
  end

  describe 'guards técnicos (sobrevivem ao D-6)' do
    it 'responds to a regular incoming message' do
      expect(should_respond?).to be true
    end

    it 'skips activity messages' do
      activity = build(:message, conversation: conversation, message_type: :activity, account: account)

      expect(should_respond?(activity)).to be false
    end

    it 'skips messages without content and without attachments' do
      empty = build(:message, conversation: conversation, message_type: :incoming, content: nil, account: account)

      expect(should_respond?(empty)).to be false
    end
  end

  describe 'skip_groups (config-gated, padrão SEGURO)' do
    before do
      assistant.update!(behavior: { 'router' => { 'skip_groups' => true } })
    end

    it 'skips when additional_attributes type is group' do
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be false
    end

    it 'skips when contact identifier ends with @g.us' do
      contact.update!(identifier: '123456789@g.us')

      expect(should_respond?).to be false
    end

    it 'skips when waha_whatsapp_chat_id ends with @g.us' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '123456789@g.us' })

      expect(should_respond?).to be false
    end

    it 'skips when waha_whatsapp_jid ends with @g.us' do
      contact.update!(custom_attributes: { 'waha_whatsapp_jid' => '123456789@g.us' })

      expect(should_respond?).to be false
    end

    it 'keeps responding on 1:1 conversations even with skip_groups on' do
      expect(should_respond?).to be true
    end

    # Padrão SEGURO: sem configuração explícita a IA NÃO fala dentro do grupo. Antes desta
    # mudança a chave ausente liberava a resposta — 2 dos 8 assistants desta base estavam
    # exatamente nesse estado (Helena e Lia, sem `skip_groups` no behavior).
    it 'skips group conversations by default when skip_groups is not configured' do
      assistant.update!(behavior: { 'router' => {} })
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be false
    end

    it 'skips group conversations by default when the router config is absent entirely' do
      assistant.update!(behavior: {})
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be false
    end

    it 'still responds on 1:1 conversations when skip_groups is not configured' do
      assistant.update!(behavior: { 'router' => {} })

      expect(should_respond?).to be true
    end

    # Quem DESLIGOU o guard de propósito continua mandando: é o escape hatch da conta que quer
    # a IA dentro do grupo. Só a ausência da chave cai no default seguro.
    it 'responds inside a group when skip_groups is explicitly false' do
      assistant.update!(behavior: { 'router' => { 'skip_groups' => false } })
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be true
    end

    it 'responds inside a group when skip_groups is the string "false" (config vinda de JSON)' do
      assistant.update!(behavior: { 'router' => { 'skip_groups' => 'false' } })
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be true
    end

    it 'skips a group when skip_groups is the string "true" (config vinda de JSON)' do
      assistant.update!(behavior: { 'router' => { 'skip_groups' => 'true' } })
      conversation.update!(additional_attributes: { 'type' => 'group' })

      expect(should_respond?).to be false
    end
  end

  # skip_labels NÃO é guard de negócio e não morreu com o gate por atribuição: ele foi
  # RESSUSCITADO em 23/07 para o caso do interlocutor-robô (conversa marcada `bot-externo`,
  # quando o outro lado é a URA de outra empresa). Cala a IA de forma determinística, sem
  # gastar LLM. O exemplo que vivia aqui afirmava o contrário e estava vermelho desde então.
  describe 'kill-switch por label (skip_labels)' do
    it 'does not respond when a conversation label matches skip_labels' do
      assistant.update!(behavior: { 'router' => { 'skip_labels' => ['atendimento'] } })
      conversation.update_labels(['atendimento'])

      expect(should_respond?).to be false
    end

    it 'responds when no label matches' do
      assistant.update!(behavior: { 'router' => { 'skip_labels' => ['bot-externo'] } })
      conversation.update_labels(['atendimento'])

      expect(should_respond?).to be true
    end

    it 'responds when skip_labels is not configured' do
      expect(should_respond?).to be true
    end
  end

  # Etiquetas que a IA não atende (CHAT-180): configuração da CONTA, vale para qualquer IA dela.
  describe 'etiquetas sem IA da conta (captain_etiquetas_sem_ia)' do
    def configurar(*etiquetas)
      account.update!(custom_attributes: { 'captain_etiquetas_sem_ia' => etiquetas })
    end

    it 'does not respond when the conversation has a configured label' do
      configurar('portaria')
      conversation.update_labels(['portaria'])

      expect(should_respond?).to be false
    end

    it 'does not respond when the contact has a configured label' do
      configurar('portaria')
      contact.update_labels(['portaria'])

      expect(should_respond?).to be false
    end

    it 'responds when the conversation label is not configured' do
      configurar('portaria')
      conversation.update_labels(['atendimento'])

      expect(should_respond?).to be true
    end

    it 'responds when the account has no configuration' do
      conversation.update_labels(['portaria'])

      expect(should_respond?).to be true
    end
  end

  # Trava de teste (CHAT-171): com only_contact_phones preenchido, a IA só fala com esses
  # telefones. O contato do spec é +55 65 99911-1222.
  describe 'trava de teste (only_contact_phones)' do
    def travar(*telefones)
      assistant.update!(behavior: { 'router' => { 'only_contact_phones' => telefones } })
    end

    it 'does not respond to a contact outside the list' do
      travar('+5511888887777')

      expect(should_respond?).to be false
    end

    it 'responds to a contact in the list written the same way' do
      travar('+5565999111222')

      expect(should_respond?).to be true
    end

    it 'matches the list entry without the ninth digit' do
      travar('556599111222')

      expect(should_respond?).to be true
    end

    it 'matches the list entry without the country code' do
      travar('(65) 99911-1222')

      expect(should_respond?).to be true
    end

    it 'matches by the WAHA JID when the contact has no phone number' do
      contact.update!(phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => '556599111222@c.us' })
      travar('+5565999111222')

      expect(should_respond?).to be true
    end

    it 'does not respond when the contact has no phone at all' do
      contact.update!(phone_number: nil)
      travar('+5565999111222')

      expect(should_respond?).to be false
    end

    it 'keeps responding to everyone when the list is empty' do
      travar('', nil)

      expect(should_respond?).to be true
    end
  end

  describe 'guards de negócio mortos (papel assumido pelo gate por atribuição)' do
    it 'responds even with skip_agent_bot config (bug latente não portado)' do
      assistant.update!(behavior: { 'router' => { 'skip_agent_bot' => true } })
      conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)

      expect(should_respond?).to be true
    end

    it 'responds even with skip_after_human_response config and a last human outgoing (guard morto no router)' do
      assistant.update!(behavior: { 'router' => { 'skip_after_human_response' => true } })
      create(:message, conversation: conversation, message_type: :outgoing, account: account)
      # dono=espelho forçado: no nível integrado quem cala a IA é a perda do dono (A2c),
      # não o router — ver spec do HookExecutionService.
      conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)

      expect(should_respond?).to be true
    end
  end
end
