# frozen_string_literal: true

# BLOCO 2.13 — o `release` que o relatório de erro do widget carrega.
#
# O QUE ESTAVA QUEBRADO: `widget/helpers/telemetry.js:149` lê
# `window.chatwootWebChannel?.release ?? null` desde que o bloco nasceu, e NENHUM dos dois
# montadores publicava a chave. Resultado medido: `release` chegava `null` ao GlitchTip em
# toda instalação da frota — o único lugar onde ele tinha valor era o harness de E2E, que o
# fabricava (`spec/e2e/telemetry/harness/hostServer.js:78`, `release: 'v-teste'`). Um teste
# que só lesse o harness confirmaria o campo para sempre sem que o produto o publicasse
# nunca, que é exatamente o defeito que este arquivo existe para não deixar acontecer de
# novo.
#
# POR QUE IMPORTA: é a primeira pergunta de qualquer triagem de erro de widget — o
# navegador do visitante está com o build de hoje ou com um de três deploys atrás preso em
# cache? Sem `release` no evento, não há como responder.
#
# ESTE SPEC ACUSA: renderiza a página de verdade e chama o endpoint de verdade, e exige a
# MESMA versão nos dois. A paridade de CHAVE já é cobrada por
# `widget_configuration_builder_parity_spec.rb`; o que ela não vê — e este arquivo vê — é
# os dois montadores publicando a chave com valor vazio.
require 'rails_helper'

RSpec.describe 'O `release` no payload de boot do widget', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  def erb_release
    get widget_url(website_token: web_widget.website_token)
    expect(response).to be_successful

    response.body[/^\s*release:\s*'(?<valor>[^']*)'/, :valor]
  end

  def jbuilder_release
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    response.parsed_body.fetch('website_channel_config')['release']
  end

  it 'o ERB publica a versão em execução, e não vazio' do
    # `be_present` e não só `eq(...)`: a comparação com a mesma leitura passaria também se as
    # duas devolvessem `nil`, que é precisamente o estado anterior a este bloco.
    expect(Chatwoot.config[:version]).to be_present
    expect(erb_release).to eq(Chatwoot.config[:version])
  end

  it 'o jbuilder de `configs` publica a mesma versão' do
    # Este jbuilder é o substituto planejado do controller do ERB
    # (`widgets_controller.rb:1`). Chave que existisse só num dos dois lados mataria a
    # telemetria por versão no dia da troca, em silêncio.
    expect(jbuilder_release).to eq(Chatwoot.config[:version])
  end

  it 'os dois montadores publicam O MESMO valor' do
    # Um exemplo, e não um por montador: dois exemplos separados passariam com valores
    # DIFERENTES, cada um comparando com a sua própria expectativa.
    expect(erb_release).to eq(jbuilder_release)
  end
end
