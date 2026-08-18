# frozen_string_literal: true

require 'rails_helper'

# 4.02 (BK-21) — ACEITE: "dois fluxos ativos entregam fluxos diferentes conforme a URL; o widget
# NUNCA recebe a definicao completa".
#
# Mede o caminho inteiro, do jeito que um visitante o percorre: o widget cria a conversa com a URL
# de origem (`referer_url`), o servidor resolve QUAL fluxo `widget_prechat` atende aquela URL
# (Flows::WidgetPrechatResolver) e entrega o passo como MENSAGEM. O payload que o widget le e
# entao inspecionado inteiro: nenhum pedaco da definicao pode estar la.
RSpec.describe 'Entrega do fluxo de pre-chat pela URL (4.02)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  after { Current.reset }

  # A inbox declara que o pre-chat dela e um fluxo — o modo que a tela 3.14 grava.
  before do
    web_widget.update!(pre_chat_form_enabled: true,
                       pre_chat_form_options: web_widget.pre_chat_form_options.merge('mode' => 'flow'))
  end

  def prechat_flow(name:, greeting:, trigger_config:)
    create(:flow, account: account, name: name, trigger_type: :widget_prechat,
                  trigger_config: trigger_config,
                  definition: {
                    'nodes' => [{ 'id' => 'greet', 'type' => 'action', 'action_name' => 'send_message',
                                  'action_params' => [greeting] }],
                    'edges' => []
                  })
  end

  # O visitante abre o chat numa URL e manda a primeira mensagem: e aqui que a conversa nasce
  # (widget/base_controller#create_conversation) carregando o `referer`.
  def first_message_from(url)
    clear_enqueued_jobs
    post api_v1_widget_messages_url,
         params: { website_token: web_widget.website_token,
                   message: { content: 'oi', referer_url: url, timestamp: Time.current.to_i } },
         headers: { 'X-Auth-Token' => token },
         as: :json
    perform_enqueued_jobs(only: EventDispatcherJob)
  end

  def widget_messages
    get api_v1_widget_messages_url,
        params: { website_token: web_widget.website_token },
        headers: { 'X-Auth-Token' => token },
        as: :json
    response.parsed_body['payload']
  end

  describe 'two active flows with different URL criteria' do
    before do
      account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
      prechat_flow(name: 'Captura de precos', greeting: 'Quer um orcamento?',
                   trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })
      prechat_flow(name: 'Captura de suporte', greeting: 'Qual e o problema?',
                   trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/suporte' }] })
    end

    it 'delivers the pricing flow to a visitor coming from /precos' do
      first_message_from('https://site.exemplo.com.br/precos?plano=pro')

      contents = widget_messages.pluck('content')
      expect(contents).to include('Quer um orcamento?')
      expect(contents).not_to include('Qual e o problema?')
    end

    it 'delivers the support flow to a visitor coming from /suporte' do
      first_message_from('https://site.exemplo.com.br/suporte/abrir-chamado')

      contents = widget_messages.pluck('content')
      expect(contents).to include('Qual e o problema?')
      expect(contents).not_to include('Quer um orcamento?')
    end

    it 'delivers no prechat flow when the URL matches neither' do
      first_message_from('https://site.exemplo.com.br/blog/post-1')

      contents = widget_messages.pluck('content')
      expect(contents).not_to include('Quer um orcamento?', 'Qual e o problema?')
    end

    # A metade do aceite que protege o cliente: a definicao carrega a logica de qualificacao
    # (quem e lead bom, o que desqualifica, para onde vai cada ramo). Entrega-la ao navegador
    # e publica-la.
    it 'never ships the flow definition, the criteria or the flow list to the widget' do
      first_message_from('https://site.exemplo.com.br/precos')

      get api_v1_widget_messages_url,
          params: { website_token: web_widget.website_token },
          headers: { 'X-Auth-Token' => token },
          as: :json

      expect(response).to have_http_status(:success)
      body = response.body
      expect(body).to include('Quer um orcamento?') # o passo chegou...
      ['url_conditions', 'trigger_config', 'definition', '"nodes"', '"edges"', 'action_name', 'Captura'].each do |leak|
        expect(body).not_to include(leak), "o payload do widget vazou #{leak}"
      end
    end
  end

  describe 'tie-break between two flows that both match' do
    before do
      account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
    end

    it 'prefers the more specific flow over the catch-all' do
      prechat_flow(name: 'Padrao da conta', greeting: 'Como posso ajudar?', trigger_config: {})
      prechat_flow(name: 'Captura de precos', greeting: 'Quer um orcamento?',
                   trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })

      first_message_from('https://site.exemplo.com.br/precos')

      contents = widget_messages.pluck('content')
      expect(contents).to include('Quer um orcamento?')
      expect(contents).not_to include('Como posso ajudar?')
    end

    it 'falls back to the catch-all when no specific flow matches the URL' do
      prechat_flow(name: 'Padrao da conta', greeting: 'Como posso ajudar?', trigger_config: {})
      prechat_flow(name: 'Captura de precos', greeting: 'Quer um orcamento?',
                   trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })

      first_message_from('https://site.exemplo.com.br/blog')

      expect(widget_messages.pluck('content')).to include('Como posso ajudar?')
    end
  end

  describe 'with the flows engine OFF' do
    it 'delivers nothing (nada muda)' do
      prechat_flow(name: 'Captura de precos', greeting: 'Quer um orcamento?',
                   trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })

      first_message_from('https://site.exemplo.com.br/precos')

      expect(widget_messages.pluck('content')).not_to include('Quer um orcamento?')
      expect(FlowRun.count).to eq(0)
    end
  end
end
