# frozen_string_literal: true

require 'rails_helper'

# Mecanismo de aceite do bloco 2.14 — degradação do launcher.
#
# ACEITE (§2.2): «Bloqueando o bundle no devtools, o link alternativo aparece».
#
# Este arquivo cobre o CONTRATO do snippet: o que o servidor entrega para o
# cliente colar no site dele. O comportamento em navegador — bloquear o bundle
# de verdade e ver o link nascer — é medido em `spec/e2e/fallback/`, com config
# de Playwright próprio.
#
# O QUE ESTAVA ERRADO: o snippet só tinha `g.onload`. Quando o `sdk.js` não
# carrega — bloqueador de conteúdo, `script-src` da CSP do cliente, rede do
# visitante, CDN fora — nada acontecia: nenhum launcher, nenhum aviso, e o
# visitante ficava sem canal de contato sem que ninguém soubesse. `onload` que
# nunca dispara não é erro para ninguém.
RSpec.describe Channel::WebWidget do
  let!(:channel_widget) { create(:channel_widget) }
  let(:snippet) { channel_widget.web_widget_script }

  describe 'o snippet reage ao bundle que não carrega' do
    it 'registra um manipulador de erro no elemento de script' do
      expect(snippet).to include('g.onerror')
    end

    it 'também cobre o bundle que fica pendurado, com um prazo' do
      # `onerror` não é garantido: parte dos bloqueadores de conteúdo apenas
      # descarta a requisição, e o `script` fica pendente sem nunca falhar nem
      # carregar. Sem prazo, esse caso — o mais comum dos dois — passaria
      # despercebido.
      expect(snippet).to include('setTimeout')
      expect(snippet).to match(/setTimeout\([^,]+,\s*\d+\)/)
    end

    it 'não mostra a alternativa se o SDK já subiu' do
      # Protege contra o falso positivo do prazo em rede lenta: o link não pode
      # brotar ao lado de um widget que funciona.
      expect(snippet).to include('window.$chatwoot')
    end

    it 'expõe a ponte que o SDK usa para retirar a alternativa' do
      # Contrato com `entrypoints/sdk.js`: quando o SDK finalmente roda depois
      # do prazo, ele chama `hide()`. Se esta chave mudar de nome aqui e não
      # lá, o link fica preso na tela — é o tipo de junção que passa por 100%
      # dos testes de cada lado isolado.
      expect(snippet).to include('window.chatwootFallback')
      expect(snippet).to include('show')
      expect(snippet).to include('hide')
    end
  end

  describe 'para onde o link alternativo aponta' do
    it 'usa a página própria do widget quando o cliente não configurou nada' do
      expect(snippet).to include("/widget?website_token=#{channel_widget.website_token}")
    end

    it 'permite que o cliente aponte para o canal dele' do
      # WhatsApp, telefone, e-mail: quem conhece o canal alternativo é o dono
      # do site, não nós.
      expect(snippet).to include('fallbackUrl')
      expect(snippet).to include('fallbackLabel')
    end

    it 'abre em aba nova sem entregar a janela de origem' do
      expect(snippet).to include('noopener')
      expect(snippet).to include('noreferrer')
    end
  end

  describe 'o rótulo do link segue o idioma da conta' do
    it 'sai em português para conta em pt_BR' do
      channel_widget.account.update!(locale: 'pt_BR')

      expect(channel_widget.reload.web_widget_script).to include('Falar por outro canal')
    end

    it 'sai em inglês para conta em inglês' do
      channel_widget.account.update!(locale: 'en')

      expect(channel_widget.reload.web_widget_script).to include('Talk to us another way')
    end

    it 'não deixa o rótulo quebrar a string JavaScript' do
      # O rótulo é interpolado dentro de uma string JS. Aspas ou barra
      # invertida sem escape fechariam a string e o snippet inteiro pararia de
      # ser JavaScript válido — sabotando exatamente o caminho de degradação
      # que este bloco existe para criar.
      expect(snippet).not_to match(/=\s*'[^']*'[^']*'\s*;/)
    end
  end

  describe 'paridade com o fixture que o teste de navegador carrega' do
    # A cicatriz nº 4 da onda foi um defeito de JUNÇÃO: dois lados certos
    # sozinhos, contrato divergindo no meio. Aqui existem dois lados do mesmo
    # snippet — o gerado por este modelo e o `fixtures/snippet.html` que o
    # harness de `spec/e2e/fallback/` serve ao navegador. Se um mudar e o outro
    # não, o teste de navegador passaria medindo um snippet que ninguém entrega.
    #
    # Para regerar depois de uma mudança deliberada:
    #
    #   FRONTEND_URL=__BASE_URL__ bundle exec rails runner -e test '...'
    #
    # (o comando completo está no relatório do bloco 2.14).
    let(:fixture_path) { Rails.root.join('spec/e2e/fallback/fixtures/snippet.html') }

    it 'o fixture é byte a byte o snippet que o modelo gera' do
      # A normalização do BASE_URL é por PADRÃO, não por `gsub` do valor de
      # `FRONTEND_URL`: essa variável é vazia em boa parte dos ambientes, e
      # `gsub('', x)` insere `x` entre todos os caracteres da string — o teste
      # passaria ou falharia conforme o `.env` da máquina, que é o oposto de
      # uma guarda.
      gerado = channel_widget.web_widget_script
                             .sub(/var BASE_URL="[^"]*";/, 'var BASE_URL="__BASE_URL__";')
                             .gsub(channel_widget.website_token, '__WEBSITE_TOKEN__')

      expect(gerado).to eq(fixture_path.read),
                        'spec/e2e/fallback/fixtures/snippet.html está desatualizado — regere-o (ver o comentário acima)'
    end
  end

  describe 'o que já funcionava continua funcionando' do
    it 'mantém o carregamento normal do SDK' do
      expect(snippet).to include('g.onload')
      expect(snippet).to include('window.chatwootSDK.run')
      expect(snippet).to include(channel_widget.website_token)
    end
  end
end
