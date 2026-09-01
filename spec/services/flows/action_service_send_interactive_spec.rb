# frozen_string_literal: true

require 'rails_helper'

# Nó `send_interactive` (F1): envia lista/botões WhatsApp a partir do Flow. Espelha send_message —
# texto de serviço livre, exige a janela de 24h. Cobre o GOTCHA do MessageBuilder (com Hash puro os
# items eram apagados), a sanitização contra os limites da Meta e o compliance idêntico ao send_message.
# Sem HTTP real — MessageBuilder só cria a Message; o envio ao canal é um job que não performamos aqui.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
  let(:contact) { conversation.contact }
  let(:service) { described_class.new(flow: flow, conversation: conversation) }

  after { Current.reset }

  def run(name, params)
    service.execute({ 'type' => 'action', 'action_name' => name, 'action_params' => params })
  end

  # Abre a janela de 24h (a conversa WhatsApp nasce fora dela) com um incoming recente do contato.
  def open_window!
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     message_type: :incoming, content: 'oi', sender: contact)
  end

  def send_interactive(items, content: 'Escolha uma opção:')
    run('send_interactive', [{ 'content' => content, 'items' => items }])
    conversation.reload.messages.where(message_type: :outgoing).last
  end

  describe 'the GOTCHA — items survive the plain-Hash service-layer path' do
    before { open_window! }

    it 'persists the Message with content_type input_select and the sanitized items' do
      items = [
        { 'title' => 'Suporte', 'value' => 'suporte', 'description' => 'Falar com o time' },
        { 'title' => 'Vendas', 'value' => 'vendas' }
      ]
      result = run('send_interactive', [{ 'content' => 'Escolha uma opção:', 'items' => items }])

      expect(result.status).to eq(:success)
      message = conversation.reload.messages.where(message_type: :outgoing).last
      expect(message.content_type).to eq('input_select')
      expect(message.content).to eq('Escolha uma opção:')
      # Coração do gotcha: sem o fix no MessageBuilder, @items ficaria nil e message_params o
      # sobrescreveria — a Message nem validaria (input_select exige items). Aqui prova-se persistido.
      expect(message.content_attributes['items']).to eq(
        [
          { 'title' => 'Suporte', 'value' => 'suporte', 'description' => 'Falar com o time' },
          { 'title' => 'Vendas', 'value' => 'vendas' }
        ]
      )
    end

    it 'stamps the flow_id anti-loop marker (automation mode) alongside the items' do
      message = send_interactive([{ 'title' => 'Ok', 'value' => 'ok' }])
      expect(message.content_attributes['flow_id']).to eq(flow.id)
      expect(message.content_attributes['items'].first['title']).to eq('Ok')
    end
  end

  describe 'sanitization against Meta limits' do
    before { open_window! }

    it 'caps items at 10, truncating the excess' do
      items = Array.new(13) { |i| { 'title' => "Opt #{i}", 'value' => "v#{i}" } }
      expect(send_interactive(items).content_attributes['items'].length).to eq(10)
    end

    it 'falls back to a slug of the title when value is blank' do
      message = send_interactive([{ 'title' => 'Falar com Suporte', 'value' => '' }])
      expect(message.content_attributes['items'].first['value']).to eq('falar-com-suporte')
    end

    it 'truncates title to 24, value to 200 and description to 72' do
      message = send_interactive([{ 'title' => 'T' * 40, 'value' => 'v' * 250, 'description' => 'd' * 100 }])
      item = message.content_attributes['items'].first
      expect(item['title'].length).to eq(24)
      expect(item['value'].length).to eq(200)
      expect(item['description'].length).to eq(72)
    end

    it 'drops items without a title and omits description when absent' do
      message = send_interactive([{ 'title' => '', 'value' => 'x' }, { 'title' => 'Ok', 'value' => 'ok' }])
      items = message.content_attributes['items']
      expect(items.length).to eq(1)
      expect(items.first).not_to have_key('description')
    end

    it 'truncates the body to 1024' do
      message = send_interactive([{ 'title' => 'Ok', 'value' => 'ok' }], content: 'b' * 2000)
      expect(message.content.length).to eq(1024)
    end
  end

  describe 'guard: interactive_no_items (fires BEFORE compliance)' do
    it 'skips when items is empty — even without opening the 24h window' do
      result = run('send_interactive', [{ 'content' => 'Oi', 'items' => [] }])
      expect(result.status).to eq(:skipped)
      expect(result.error).to be_a(Flows::StepSkip).and(have_attributes(code: 'interactive_no_items'))
    end

    it 'skips when every item lacks a title (all sanitized away)' do
      result = run('send_interactive', [{ 'content' => 'Oi', 'items' => [{ 'value' => 'x' }, { 'title' => '  ' }] }])
      expect(result.error.code).to eq('interactive_no_items')
    end

    it 'does not create a Message when skipped' do
      expect { run('send_interactive', [{ 'content' => 'Oi', 'items' => [] }]) }.not_to change(Message, :count)
    end
  end

  # Menu de opções não é exclusividade do WhatsApp — mas também não é universal. Canal que não
  # desenha o menu manda só o `content`: a pergunta chega e as opções somem, sem erro nenhum.
  describe 'guard: inbox_no_interactive_items' do
    let(:items) { [{ 'title' => 'Suporte', 'value' => 'suporte' }] }

    context 'when the channel does not render menus (Instagram)' do
      let(:instagram_channel) { create(:channel_instagram, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: instagram_channel.inbox) }

      it 'skips with a triable reason instead of sending a question with no options' do
        open_window!
        result = run('send_interactive', [{ 'content' => 'Escolha:', 'items' => items }])

        expect(result.status).to eq(:skipped)
        expect(result.error).to be_a(Flows::StepSkip).and(have_attributes(code: 'inbox_no_interactive_items'))
      end

      it 'does not create a Message when skipped' do
        open_window!
        expect { run('send_interactive', [{ 'content' => 'Escolha:', 'items' => items }]) }.not_to change(Message, :count)
      end
    end

    # A guarda de canal vem ANTES do compliance: numa inbox que nunca vai desenhar o menu, o motivo
    # útil para quem tria é o canal, não a janela de 24h.
    it 'reports the channel, not the window, when both would block' do
      instagram_channel = create(:channel_instagram, account: account)
      other = create(:conversation, account: account, inbox: instagram_channel.inbox)
      result = described_class.new(flow: flow, conversation: other)
                              .execute({ 'type' => 'action', 'action_name' => 'send_interactive',
                                         'action_params' => [{ 'content' => 'Oi', 'items' => items }] })

      expect(result.error.code).to eq('inbox_no_interactive_items')
    end

    # Contraprova: a guarda não é "só WhatsApp Cloud". O Telegram desenha o menu (inline_keyboard)
    # e continua entregando.
    it 'still delivers on a non-WhatsApp channel that does render menus (Telegram)' do
      telegram_channel = create(:channel_telegram, account: account)
      other = create(:conversation, account: account, inbox: telegram_channel.inbox)
      create(:message, conversation: other, account: account, inbox: telegram_channel.inbox,
                       message_type: :incoming, content: 'oi', sender: other.contact)

      expect do
        described_class.new(flow: flow, conversation: other)
                       .execute({ 'type' => 'action', 'action_name' => 'send_interactive',
                                  'action_params' => [{ 'content' => 'Oi', 'items' => items }] })
      end.to change { other.messages.where(message_type: :outgoing).count }.by(1)
    end
  end

  describe 'compliance — idêntico ao send_message (utility, free_form)' do
    it 'skips (outside_window) a send_interactive with valid items when outside the 24h window' do
      result = run('send_interactive', [{ 'content' => 'Oi', 'items' => [{ 'title' => 'A', 'value' => 'a' }] }])
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('outside_window')
    end

    it 'delivers inside the window' do
      open_window!
      expect do
        run('send_interactive', [{ 'content' => 'Oi', 'items' => [{ 'title' => 'A', 'value' => 'a' }] }])
      end.to change { conversation.messages.where(message_type: :outgoing).count }.by(1)
    end
  end
end
