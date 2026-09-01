# frozen_string_literal: true

require 'rails_helper'

# Mecanismo de aceite do bloco 5.18 — `data-*` de CONFIGURACAO no snippet, nunca identidade.
#
# ACEITE (PLANO-MESTRE, linha 5.18): «Configuracao viaja por qualquer via; identidade e
# credencial, so pela API JS».
#
# ESTE ARQUIVO COBRE O LADO DO SERVIDOR — o texto que o cliente cola no site dele. O
# comportamento em navegador (a configuracao chegando ao `window.$chatwoot`, a recusa aparecendo
# no console, o link alternativo obedecendo a posicao) e medido em
# `spec/e2e/snippet-data/`, com Chromium, o snippet real e o `sdk.js` real.
#
# O QUE ESTAVA ERRADO, e por que um modulo com 32 exemplos verdes nao provava nada. A regra
# (`app/javascript/sdk/snippetConfig.js`) sempre esteve correta e testada. O que faltava era o
# CANO: a tag que o servidor gera nao tinha marcador nenhum — nem `data-chatspx-snippet`, nem
# `id="chatwoot-sdk"`, os dois nomes que o bundle procurava eram constantes sem escritor — e a
# leitura acontecia dentro de `g.onload`, onde `document.currentScript` e `null` por
# especificacao. Medido em Chromium com o snippet real: `snippetEl = null`, `dataset = {}`.
# Nenhuma configuracao viajava, e o `console.warn` de recusa era codigo morto.
RSpec.describe Channel::WebWidget do
  let!(:channel_widget) { create(:channel_widget) }
  let(:snippet) { channel_widget.web_widget_script }

  # O corpo do `g.onload`, isolado: e dentro DELE que a leitura nao pode acontecer.
  let(:corpo_do_onload) { snippet[/g\.onload=function\(\)\{(.*?)\n        \}/m, 1].to_s }

  describe 'a tag do snippet passa a ter marcador' do
    it 'e o marcador e `data-chatspx-snippet`' do
      expect(snippet).to include('<script data-chatspx-snippet>')
    end

    it 'e o nome que o snippet ESCREVE e o mesmo que o bundle PROCURA' do
      # A cicatriz no 4 da onda foi um defeito de JUNCAO: dois lados certos sozinhos, contrato
      # divergindo no meio. Aqui sao literalmente dois arquivos em duas linguagens; renomear o
      # marcador de um lado e nao do outro devolve o bloco ao estado em que ele nasceu — `data-*`
      # que nunca chega — sem nenhum teste de cada lado isolado ficar vermelho.
      sdk = Rails.root.join('app/javascript/entrypoints/sdk.js').read

      expect(sdk).to include('script[data-chatspx-snippet]')
      expect(snippet).to include('data-chatspx-snippet')
    end
  end

  describe 'a leitura do dataset acontece FORA do onload' do
    it 'le `d.currentScript` durante a execucao sincrona da tag' do
      expect(snippet).to include('var SNIPPET=d.currentScript')
    end

    it 'e le ANTES de registrar o onload' do
      # Ordem no texto = ordem no tempo, aqui: o corpo do `onload` so roda depois que o `sdk.js`
      # baixa. Ler depois e ler tarde.
      expect(snippet.index('var SNIPPET=')).to be < snippet.index('g.onload=')
    end

    it 'ASSERCAO NEGATIVA FORCADA — dentro do onload nao ha leitura de dataset nenhuma' do
      # A condicao ruim, forcada: se alguem mover a leitura para dentro do callback, ela volta a
      # `null` em todo navegador e o bloco morre de novo. Este exemplo passa tambem quando o
      # `onload` nao existe, entao ele confere primeiro que ha um corpo para examinar.
      expect(corpo_do_onload).to include('window.chatwootSDK.run')
      expect(corpo_do_onload).not_to include('currentScript')
      expect(corpo_do_onload).not_to include('querySelector')
      expect(corpo_do_onload).not_to include('.dataset')
    end

    it 'entrega o que leu para o `run()`, e nao deixa o bundle procurar sozinho' do
      expect(corpo_do_onload).to include('snippetDataset: SNIPPET_DATA')

      sdk = Rails.root.join('app/javascript/entrypoints/sdk.js').read
      expect(sdk).to include('snippetDataset')
    end

    it 'COPIA o dataset em vez de guardar a referencia viva' do
      # `dataset` e vivo: um CMS que reescreva o atributo depois mudaria, em silencio, a
      # configuracao que o visitante ja recebeu. A copia congela o valor do instante do parse.
      expect(snippet).to include('var SNIPPET_DATA={};')
      expect(snippet).to match(/for\(var k in SNIPPET\.dataset\)\{SNIPPET_DATA\[k\]=SNIPPET\.dataset\[k\]\}/)
    end
  end

  describe 'a regra de qual via pode carregar o que mora num lugar so' do
    let(:snippet_config) { Rails.root.join('app/javascript/sdk/snippetConfig.js').read }

    it 'o servidor nao tem allowlist propria: quem filtra e `snippetConfig.js`' do
      # Duas listas do que pode viajar divergiriam no primeiro ajuste — e a divergencia seria
      # justamente "o painel oferece a chave e o widget descarta", em silencio.
      expect(snippet).not_to include('CONFIG_KEYS')
      expect(snippet_config).to include('export const CONFIG_KEYS')
      expect(snippet_config).to include('export const IDENTITY_KEYS')
    end

    it 'a precedencia do link alternativo e a MESMA do bundle: `chatwootSettings` vence' do
      # O link do 2.14 nasce quando o bundle NAO carrega — ele nunca vera nada que o `sdk.js`
      # resolva, entao a precedencia precisa existir aqui tambem. Duas escritas da mesma regra
      # divergem no primeiro ajuste; este exemplo e o que amarra as duas.
      expect(snippet).to include('var POSITION=cfg.position||SNIPPET_DATA.position;')
      expect(snippet_config).to include('{ ...config, ...settings }')
    end

    it 'e o link alternativo usa essa posicao, nao mais so o `chatwootSettings`' do
      expect(snippet).to include('a.setAttribute("style",POSITION==="left"?')
      expect(snippet).not_to include('cfg.position==="left"')
    end
  end

  describe 'o que ja funcionava continua funcionando' do
    it 'mantem o carregamento normal, o fallback e os campos que o merge trouxe' do
      expect(snippet).to include('g.onload')
      expect(snippet).to include('g.onerror=showFallback')
      expect(snippet).to include('window.chatwootFallback')
      expect(snippet).to include('conversationToken:')
      expect(snippet).to include('persistConversationToParent:')
      expect(snippet).to include(channel_widget.website_token)
    end

    it 'o versionamento do caminho do SDK sobrevive ao marcador' do
      versionado = channel_widget.web_widget_script(sdk_version: 'abc123')

      expect(versionado).to include('/packs/js/sdk.js?v=abc123')
      expect(versionado).to include('<script data-chatspx-snippet>')
    end

    it 'a persistencia da conversa no host sobrevive ao marcador' do
      persistido = channel_widget.web_widget_script(persist_conversation_to_parent: true)

      expect(persistido).to include("get('cw_conversation')")
      expect(persistido).to include('persistConversationToParent: true')
      expect(persistido).to include('snippetDataset: SNIPPET_DATA')
    end
  end
end
