# frozen_string_literal: true

require 'rails_helper'

# Bloco 3.14 — o CONTEUDO do pre-chat entregue ao widget, nos DOIS montadores.
#
# POR QUE ESTE ARQUIVO EXISTE, e a razao e uma descoberta desta trilha:
# a suite de paridade da 0.6 (`widget_configuration_builder_parity_spec.rb`)
# compara **chaves de TOPO** — ela extrai os nomes de primeiro nivel dos dois
# montadores e cruza. A chave `mode`, que o bloco 3.14 acrescentou, e ANINHADA
# dentro de `pre_chat_form_options`. **A rede da 0.6 nao a cobre**, e dizer que
# cobre seria a mesma classe de erro que custou caro nesta execucao: confiar numa
# protecao que nao alcanca o que se acrescentou.
#
# Os dois montadores emitem o jsonb inteiro, por caminhos DIFERENTES —
# `show.html.erb:46` serializa com `.to_json.html_safe`, e
# `configs/create.json.jbuilder:14` entrega o Hash para o jbuilder serializar. Os
# dois caminhos coincidirem hoje nao e garantia: e uma coincidencia que precisa
# de mecanismo.
RSpec.describe 'Widget pre-chat payload parity', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  # Um pre-chat que usa TUDO o que os blocos 3.12 e 3.14 acrescentaram: se algum
  # deles se perder no caminho, se perde aqui.
  let(:configured_options) do
    {
      'mode' => 'builder',
      'pre_chat_message' => 'Antes de comecar, conte quem e voce',
      'pre_chat_fields' => [
        {
          'field_type' => 'standard', 'name' => 'fullName', 'label' => 'Nome', 'type' => 'text',
          'enabled' => true, 'required' => true, 'step' => 1, 'position' => 0,
          'validator' => 'junk_name'
        },
        {
          'field_type' => 'contact_attribute', 'name' => 'cpf', 'label' => 'CPF', 'type' => 'text',
          'enabled' => true, 'required' => true, 'step' => 2, 'position' => 0,
          'mask' => 'cpf', 'validator' => 'cpf',
          'help_text' => 'Usamos para achar seu pedido',
          'error_message' => 'Confira o CPF do pedido',
          'show_if' => { 'field' => 'fullName', 'operator' => 'filled' }
        }
      ]
    }
  end

  before do
    web_widget.update!(pre_chat_form_enabled: true, pre_chat_form_options: configured_options)
  end

  def erb_pre_chat_options
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    raw = response.body[/^\s*preChatFormOptions:\s*(?<value>.*?),?\s*$/m, :value]
    raise 'preChatFormOptions not found in the rendered ERB' if raw.nil?

    JSON.parse(raw)
  end

  def jbuilder_pre_chat_options
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    response.parsed_body.fetch('website_channel_config').fetch('pre_chat_form_options')
  end

  it 'delivers the very same pre-chat object through both builders' do
    expect(erb_pre_chat_options).to eq(jbuilder_pre_chat_options)
  end

  it 'delivers the form mode, which the top-level parity suite does not reach' do
    expect(erb_pre_chat_options['mode']).to eq('builder')
    expect(jbuilder_pre_chat_options['mode']).to eq('builder')
  end

  it 'delivers every per-field key added by 3.12 through both builders' do
    %w[step position mask validator help_text error_message show_if].each do |key|
      expect(erb_pre_chat_options['pre_chat_fields'][1]).to have_key(key), "#{key} missing from the ERB"
      expect(jbuilder_pre_chat_options['pre_chat_fields'][1]).to have_key(key), "#{key} missing from the jbuilder"
    end
  end

  it 'keeps the condition object intact — it is what decides whether a field is asked at all' do
    expected = { 'field' => 'fullName', 'operator' => 'filled' }

    expect(erb_pre_chat_options['pre_chat_fields'][1]['show_if']).to eq(expected)
    expect(jbuilder_pre_chat_options['pre_chat_fields'][1]['show_if']).to eq(expected)
  end

  # Auto-verificacao: sem ela, um verde aqui poderia significar "os dois lados
  # concordam" OU "o extrator devolve a mesma coisa para os dois, aconteca o que
  # acontecer". Sabotando UM lado, o teste tem de acusar.
  it 'fails when one builder loses a nested key — the gate is real, not decorative' do
    sabotaged = erb_pre_chat_options.deep_dup
    sabotaged.delete('mode')

    expect(sabotaged).not_to eq(jbuilder_pre_chat_options)
  end

  it 'does not leak flow_id, which the schema refuses on purpose' do
    expect(erb_pre_chat_options).not_to have_key('flow_id')
    expect(jbuilder_pre_chat_options).not_to have_key('flow_id')
  end
end
