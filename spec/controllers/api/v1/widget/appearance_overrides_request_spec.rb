# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tmpdir'

# 3.18 — A JUNTA, ATRAVESSADA COM A REQUISICAO DE VERDADE.
#
# O QUE ESTE ARQUIVO EXISTE PARA IMPEDIR (e ja aconteceu)
#
# O bloco 3.18 tinha, ao mesmo tempo, um spec de front verde e um request spec verde — e a
# metade "...E A TELA AVISA" do aceite estava morta em producao. Os dois testes dublavam lados
# opostos da mesma junta:
#
#   · `widget/api/specs/appearanceOverrides.spec.js` afirmava `API.post(CAMINHO, { fields })`
#     contra um `API` falso. Ele media que a funcao chama axios, nunca o que o servidor recebe.
#   · `spec/controllers/api/v1/widget/appearance_overrides_spec.rb` mandava
#     `website_token` DENTRO do corpo JSON. O widget nunca fez isso: ele nao mandava
#     `website_token` em lugar nenhum.
#
# Resultado MEDIDO nesta base, antes da correcao: a requisicao real do widget respondia **404**
# (`set_web_widget` -> `Channel::WebWidget.find_by!(website_token: nil)` -> `RecordNotFound`), o
# `.catch(() => {})` de melhor esforco a engolia, e `widget_appearance_overrides` nunca teve
# produtor. 16 exemplos verdes do outro arquivo nao viram nada disso.
#
# COMO ESTE ARQUIVO E DIFERENTE
#
# Ele nao escreve a requisicao: ele EXECUTA o modulo do produto
# (`app/javascript/widget/api/appearanceOverridesRequest.js`, que por isso nao importa nada) num
# `node` de verdade e repassa ao Rails a URL e o corpo que sairem de la. Trocar o caminho, perder
# o `website_token` ou mudar o nome do campo do corpo derruba estes exemplos, porque a requisicao
# medida passa a ser outra — que e exatamente o que nenhum dos dois testes anteriores conseguia
# perceber.
RSpec.describe '/api/v1/widget/appearance_overrides — a requisicao que o widget monta (3.18)', type: :request do
  # O modulo do produto que este spec executa. Nao e constante para nao vazar para o `Object`
  # (o `describe` e um bloco no topo do arquivo).
  let(:modulo_da_requisicao) { 'app/javascript/widget/api/appearanceOverridesRequest.js' }

  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end
  # O `search` do iframe, ao pe da letra: `sdk/IFrameHelper.js:119-134` monta o `src` como
  # `${baseUrl}/widget?website_token=${websiteToken}` e cola `&cw_conversation=` quando ha cookie.
  let(:search_do_iframe) { "?website_token=#{web_widget.website_token}&cw_conversation=cookie-de-sessao" }

  after { Current.reset }

  # Executa o modulo do produto e devolve `{ 'url' => ..., 'body' => ... }` (ou `nil`).
  #
  # A fonte e COPIADA para um `.mjs` porque o `package.json` deste repo nao declara
  # `"type": "module"` — sem a extensao o `node` leria um arquivo com `export` como CommonJS. A
  # copia e fiel porque o modulo nao tem `import` nenhum; se um dia ganhar um, o `node` falha
  # ruidosamente aqui (resolucao de import), que e o comportamento desejado: este spec deixa de
  # medir a coisa certa e precisa saber disso.
  def requisicao_do_widget(search:, fields:)
    fonte = Rails.root.join(modulo_da_requisicao).read

    saida = Dir.mktmpdir('spx-b318') do |dir|
      File.write(File.join(dir, 'modulo.mjs'), fonte)
      File.write(File.join(dir, 'driver.mjs'), <<~JS)
        import { buildAppearanceOverridesRequest } from './modulo.mjs';
        const entrada = JSON.parse(process.env.ENTRADA_DO_SPEC);
        process.stdout.write(JSON.stringify(buildAppearanceOverridesRequest(entrada) ?? null));
      JS

      stdout, stderr, status = Open3.capture3(
        { 'ENTRADA_DO_SPEC' => { search: search, fields: fields }.to_json },
        'node', File.join(dir, 'driver.mjs')
      )
      raise "node falhou ao executar #{modulo_da_requisicao}: #{stderr}" unless status.success?

      stdout
    end

    JSON.parse(saida)
  end

  def reporta_como_o_widget(fields, search: nil)
    requisicao = requisicao_do_widget(search: search || search_do_iframe, fields: fields)
    return nil if requisicao.nil?

    post requisicao['url'],
         params: requisicao['body'],
         headers: { 'X-Auth-Token' => token },
         as: :json
    requisicao
  end

  def gravado
    inbox.reload.additional_attributes['widget_appearance_overrides']
  end

  describe 'a requisicao do produto chega ao servidor' do
    it 'a URL montada pelo widget leva o `website_token` que o `set_web_widget` exige' do
      # A assercao positiva sobre a URL vem ANTES do status para que a queda nomeie a causa: sem
      # esta chave o resto e 404, e foi assim que a metade do aceite morreu.
      requisicao = requisicao_do_widget(search: search_do_iframe, fields: %w[position])

      expect(requisicao['url']).to include("website_token=#{web_widget.website_token}")
      expect(requisicao['body']).to eq({ 'fields' => %w[position] })
    end

    it 'grava os campos que o site sobrescreve' do
      reporta_como_o_widget(%w[position theme])

      expect(response).to have_http_status(:no_content)
      expect(gravado).to eq(%w[theme position])
    end

    it 'a lista VAZIA tambem atravessa — e o que apaga um aviso que ficou velho' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance_overrides' => %w[position]))

      reporta_como_o_widget([])

      expect(response).to have_http_status(:no_content)
      expect(gravado).to eq([])
    end

    it 'o corpo real e o unico aceito: o servidor le `fields`, e nao outro nome' do
      requisicao = requisicao_do_widget(search: search_do_iframe, fields: %w[position])
      corpo_sabotado = { 'campos' => requisicao['body']['fields'] }

      post requisicao['url'], params: corpo_sabotado, headers: { 'X-Auth-Token' => token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(gravado).to be_nil
    end
  end

  describe 'a condicao ruim, FORCADA' do
    it 'sem `website_token` o servidor responde 404 e nada e gravado — o defeito que este bloco corrigiu' do
      # Isto NAO e hipotese: e literalmente a requisicao que `appearanceOverrides.js` mandava
      # antes desta revisao (`API.post('/api/v1/widget/appearance_overrides', { fields })`).
      # O exemplo fica para sempre porque ele trava as DUAS formas de o defeito voltar: alguem
      # tirar o token da URL do widget (ai o exemplo positivo acima cai) e alguem "consertar" o
      # 404 afrouxando o `set_web_widget` para nao exigir o token (ai cai este).
      post '/api/v1/widget/appearance_overrides',
           params: { fields: %w[position theme] },
           headers: { 'X-Auth-Token' => token },
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(gravado).to be_nil
    end

    it 'o modulo se recusa a montar requisicao sem `website_token` — 404 nao vira ida a rede' do
      # `search` sem o token existe de verdade: e um popout aberto na mao, ou um iframe cujo
      # `src` perdeu a query. Devolver `null` e o unico jeito de esse caso ser observavel, porque
      # o `.catch` de melhor esforco torna 404 e 204 indistinguiveis para quem chama.
      expect(requisicao_do_widget(search: '?cw_conversation=so-o-cookie', fields: %w[position])).to be_nil
      expect(requisicao_do_widget(search: '', fields: %w[position])).to be_nil
    end

    it '`fields` que nao e array nao vira requisicao — ausencia nao e medicao' do
      expect(requisicao_do_widget(search: search_do_iframe, fields: nil)).to be_nil
    end
  end

  # A CLAUSULA INTEIRA DO §2.2, ponta a ponta: "com `chatwootSettings.position` presente no site,
  # o widget usa o do site E A TELA AVISA". A primeira metade e do SDK (`sdk/appearance.js`); esta
  # e a segunda, e ela so esta fechada quando o aviso chega ao JSON que a tela realmente le.
  describe 'e a tela avisa' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'o que o widget reportou aparece no payload do painel — com o serializador de verdade' do
      # O banco diz `left`; o site do cliente escreveu `chatwootSettings.position` e venceu.
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance' => { 'position' => 'left' }))

      reporta_como_o_widget(%w[position])
      expect(response).to have_http_status(:no_content)

      get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload'].find { |i| i['id'] == inbox.id }
      # `AppearancePage.vue` le exatamente este caminho para decidir se mostra o aviso.
      expect(payload.dig('additional_attributes', 'widget_appearance_overrides')).to eq(%w[position])
      # ...e o campo continua mostrando o que o admin configurou, que e a outra metade do aviso.
      expect(payload.dig('additional_attributes', 'widget_appearance', 'position')).to eq('left')
    end

    it 'sem relatorio o painel nao inventa aviso — a chave simplesmente nao esta la' do
      inbox # a inbox precisa existir sem que ninguem tenha reportado nada

      get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].find { |i| i['id'] == inbox.id }
      expect(payload['additional_attributes']).not_to have_key('widget_appearance_overrides')
    end
  end
end
