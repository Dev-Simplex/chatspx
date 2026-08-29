# frozen_string_literal: true

require 'rails_helper'

# 4.02 — A JUNTA: `pre_chat_form_options.mode` chega ao widget?
#
# O widget passou a RAMIFICAR por essa chave (`widget/helpers/preChatMode.js`): no modo `flow` ele
# nao monta o formulario classico, porque quem faz o pre-chat e o fluxo de captura. Uma decisao de
# ramo so vale o que vale o dado que a alimenta — e o jeito conhecido de este bloco quebrar em
# producao e a chave nunca chegar, com toda a suite do front verde por cima de um dublê.
#
# Por isso a medicao e aqui, contra os montadores REAIS e nos DOIS (regra do bloco 0.6): o ERB de
# `widgets/show.html.erb`, que escreve `window.chatwootWebChannel`, e o jbuilder de
# `/api/v1/widget/config`. O spec do front (`widget/specs/preChatModoFluxo.spec.js`) monta o dublê
# com a forma que ESTE spec confere: contêiner camelCase (`preChatFormOptions`) com as chaves
# internas CRUAS, snake_case, porque os dois montadores fazem `.to_json` do hash do banco sem
# camelizar.
RSpec.describe 'mode do pre-chat no payload do widget (4.02)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  # O `preChatFormOptions` do ERB, lido de volta como Hash — o mesmo recorte que
  # `spec/requests/widget_configuration_payload_spec.rb` usa para as chaves da Onda 2.
  def erb_pre_chat_form_options
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    raw = response.body[/^\s*preChatFormOptions:\s*(?<value>.*?),?\s*$/, :value]
    raise 'preChatFormOptions nao encontrado em window.chatwootWebChannel' if raw.nil?

    JSON.parse(raw)
  end

  def jbuilder_pre_chat_form_options
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    response.parsed_body.fetch('website_channel_config').fetch('pre_chat_form_options')
  end

  def gravar_modo!(mode)
    web_widget.update!(pre_chat_form_enabled: true,
                       pre_chat_form_options: web_widget.pre_chat_form_options.merge('mode' => mode))
  end

  describe 'inbox que delega o pre-chat ao fluxo de captura' do
    before { gravar_modo!('flow') }

    it 'entrega mode: "flow" no ERB, snake_case, dentro de preChatFormOptions' do
      options = erb_pre_chat_form_options

      expect(options['mode']).to eq('flow')
      # a chave e CRUA: se algum dia alguem camelizar o hash, o widget passa a ler `undefined` e
      # volta a montar os dois pre-chats — sem erro nenhum, que e o pior modo de quebrar.
      expect(options.keys).to include('mode', 'pre_chat_fields')
      expect(options.keys).not_to include('preChatFields')
    end

    it 'entrega o mesmo mode no jbuilder de /api/v1/widget/config' do
      expect(jbuilder_pre_chat_form_options['mode']).to eq('flow')
    end
  end

  # CONTROLE NEGATIVO — o estado de TODA a frota hoje. A chave nasceu no 3.14 e nao ha backfill.
  describe 'inbox que nunca escolheu um modo' do
    it 'nao inventa a chave em nenhum dos dois montadores' do
      expect(erb_pre_chat_form_options).not_to have_key('mode')
      expect(jbuilder_pre_chat_form_options).not_to have_key('mode')
    end
  end

  # O outro modo do enum tem de viajar igual: se so `flow` chegasse, o widget nunca conseguiria
  # distinguir "construtor" de "ausente", e o teste acima passaria por coincidencia.
  describe 'inbox no construtor' do
    before { gravar_modo!('builder') }

    it 'entrega mode: "builder" nos dois montadores' do
      expect(erb_pre_chat_form_options['mode']).to eq('builder')
      expect(jbuilder_pre_chat_form_options['mode']).to eq('builder')
    end
  end
end
