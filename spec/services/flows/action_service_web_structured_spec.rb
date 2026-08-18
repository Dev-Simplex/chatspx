# frozen_string_literal: true

require 'rails_helper'

# 4.02 (BK-22) — "o mesmo Flow roda nos dois canais, com renderizacao adequada em cada um".
#
# Duas metades:
#  · os LIMITES de uma mensagem estruturada passam a depender do canal. Ate aqui todo titulo era
#    truncado em 24 caracteres (limite da Meta) inclusive no chat de site, onde nao vale.
#  · `send_form`: o no que emite uma mensagem `form` no canal web — o par de envio da resposta que
#    o bloco 4.01 passou a receber.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              sync_templates: false, validate_provider_config: false)
  end

  after { Current.reset }

  def run_on(conversation, name, params)
    described_class.new(flow: flow, conversation: conversation)
                   .execute({ 'type' => 'action', 'action_name' => name, 'action_params' => params })
  end

  def last_outgoing(conversation)
    conversation.reload.messages.where(message_type: :outgoing).last
  end

  # A conversa WhatsApp nasce FORA da janela de 24h; um incoming recente a abre.
  def whatsapp_conversation
    conversation = create(:conversation, account: account, inbox: whatsapp_channel.inbox)
    create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                     message_type: :incoming, content: 'oi', sender: conversation.contact)
    conversation
  end

  def web_conversation
    create(:conversation, account: account, inbox: web_widget.inbox)
  end

  describe 'send_interactive — os limites seguem o canal' do
    let(:long_title) { 'Falar com o time financeiro sobre a fatura' } # 42 caracteres

    it 'no WhatsApp continua cortando o titulo em 24 (limite da Meta)' do
      conversation = whatsapp_conversation

      run_on(conversation, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => [{ 'title' => long_title, 'value' => 'fin' }] }])

      item = last_outgoing(conversation).content_attributes['items'].first
      expect(item['title']).to eq(long_title[0, 24])
      expect(item['title'].length).to eq(24)
    end

    it 'no chat de site entrega o titulo INTEIRO — o widget nao tem o corte da Meta' do
      conversation = web_conversation

      run_on(conversation, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => [{ 'title' => long_title, 'value' => 'fin' }] }])

      item = last_outgoing(conversation).content_attributes['items'].first
      expect(item['title']).to eq(long_title)
    end

    it 'mantem o `value` com o MESMO corte nos dois canais — ele e o branch do wait_for_reply' do
      long_value = 'v' * 250

      web = web_conversation
      run_on(web, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => [{ 'title' => 'Ok', 'value' => long_value }] }])
      zap = whatsapp_conversation
      run_on(zap, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => [{ 'title' => 'Ok', 'value' => long_value }] }])

      web_value = last_outgoing(web).content_attributes['items'].first['value']
      zap_value = last_outgoing(zap).content_attributes['items'].first['value']
      expect(web_value).to eq(zap_value)
      expect(web_value.length).to eq(200)
    end

    it 'aceita mais opcoes no chat de site (20) do que no WhatsApp (10)' do
      items = Array.new(15) { |i| { 'title' => "Opcao #{i}", 'value' => "o#{i}" } }

      web = web_conversation
      run_on(web, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => items }])
      zap = whatsapp_conversation
      run_on(zap, 'send_interactive', [{ 'content' => 'Escolha:', 'items' => items }])

      expect(last_outgoing(web).content_attributes['items'].length).to eq(15)
      expect(last_outgoing(zap).content_attributes['items'].length).to eq(10)
    end
  end

  describe 'send_form' do
    it 'emite uma mensagem `form` com os campos saneados no canal web' do
      conversation = web_conversation

      result = run_on(conversation, 'send_form', [{
                        'content' => 'Para comecar, seus dados:',
                        'button_label' => 'Enviar',
                        'items' => [{ 'name' => 'nome', 'label' => 'Seu nome', 'required' => true },
                                    { 'name' => 'email', 'label' => 'E-mail', 'type' => 'email', 'placeholder' => 'voce@empresa.com' }]
                      }])

      expect(result.status).to eq(:success)
      message = last_outgoing(conversation)
      expect(message.content_type).to eq('form')
      expect(message.content).to eq('Para comecar, seus dados:')
      expect(message.content_attributes['button_label']).to eq('Enviar')
      expect(message.content_attributes['items']).to eq(
        [{ 'name' => 'nome', 'label' => 'Seu nome', 'type' => 'text', 'required' => true },
         { 'name' => 'email', 'label' => 'E-mail', 'type' => 'email', 'required' => false, 'placeholder' => 'voce@empresa.com' }]
      )
    end

    it 'corta em 8 campos — o mesmo teto que o BK-23 recusa salvar' do
      conversation = web_conversation

      run_on(conversation, 'send_form',
             [{ 'content' => 'Dados', 'items' => Array.new(12) { |i| { 'name' => "campo#{i}" } } }])

      expect(last_outgoing(conversation).content_attributes['items'].length).to eq(8)
    end

    it 'descarta campo sem nome e cai em `text` num tipo que o widget nao desenha' do
      conversation = web_conversation

      run_on(conversation, 'send_form',
             [{ 'content' => 'Dados', 'items' => [{ 'label' => 'sem nome' }, { 'name' => 'x', 'type' => 'datepicker' }] }])

      items = last_outgoing(conversation).content_attributes['items']
      expect(items.length).to eq(1)
      expect(items.first).to include('name' => 'x', 'type' => 'text')
    end

    it 'pula (triavel, sem Sentry) fora do canal web, porque `form` so renderiza no chat de site' do
      conversation = whatsapp_conversation

      result = run_on(conversation, 'send_form', [{ 'content' => 'Dados', 'items' => [{ 'name' => 'nome' }] }])

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('form_unsupported_channel')
      expect(last_outgoing(conversation)).to be_nil
    end

    it 'pula quando nenhum campo sobrevive ao saneamento' do
      conversation = web_conversation

      result = run_on(conversation, 'send_form', [{ 'content' => 'Dados', 'items' => [{ 'label' => 'sem nome' }] }])

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('form_no_fields')
    end
  end
end
