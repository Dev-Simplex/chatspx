/**
 * Harness do bloco 2.14 — degradação do launcher.
 *
 * PORTA EFÊMERA E SERVIDOR NO PRÓPRIO PROCESSO DO TESTE, de propósito.
 *
 * O harness de porta fixa do widget (3038/3999/8899) é recurso de slot único
 * disputado por várias trilhas: entre `ss` dizer "livre" e o bind acontecer há
 * uma janela de segundos, e uma corrida que "confere e entra" perde para outra
 * — o sintoma é `Process from config.webServer exited early`, que parece
 * arquivo quebrado e é contenção. Aqui pedimos `listen(0)`: o sistema dá a
 * porta, nada é conferido porque nada é disputado, e não há `webServer` no
 * config para colidir.
 *
 * O que ele serve:
 *   · `/`                 → página hospedeira com o snippet REAL do cliente
 *   · `/packs/js/sdk.js`  → SDK mínimo, só o que o snippet toca
 *   · `/widget?…`         → destino do link alternativo, para o `href` ser
 *                           navegável de verdade
 *
 * O snippet NÃO é escrito aqui: vem de `fixtures/snippet.html`, gerado por
 * `Channel::WebWidget#web_widget_script` e conferido byte a byte por
 * `spec/models/channel/web_widget_fallback_snippet_spec.rb`. Escrevê-lo à mão
 * aqui criaria duas versões do mesmo contrato — a forma de defeito que esta
 * onda mais pagou caro (o "read-filter/write-replace" da Onda 0).
 */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const SNIPPET = fs.readFileSync(
  path.join(__dirname, '..', 'fixtures', 'snippet.html'),
  'utf-8'
);

const TOKEN_DE_TESTE = 'token-de-teste-2-14';

// SDK de mentira: o teste não mede o widget, mede o caminho de degradação.
// Precisa só do que o snippet toca — `window.chatwootSDK.run` — e de marcar
// `$chatwoot`, que é o sinal de "subiu" que `showFallback` consulta.
const SDK_FALSO = `
window.chatwootSDK = {
  run: function (options) {
    window.$chatwoot = { hasLoaded: true, options: options };
    window.chatwootFallback && window.chatwootFallback.hide();
  },
};
`;

const paginaCom = (origem, settings) => {
  const snippet = SNIPPET.split('__BASE_URL__')
    .join(origem)
    .split('__WEBSITE_TOKEN__')
    .join(TOKEN_DE_TESTE);

  return `<!doctype html>
<html lang="pt-BR">
  <head><meta charset="utf-8"><title>Site do cliente</title></head>
  <body>
    <main><h1>Loja do cliente</h1></main>
    <script>window.chatwootSettings = ${JSON.stringify(settings)};</script>
${snippet}
  </body>
</html>`;
};

const CHAVES_DE_SETTINGS = ['position', 'fallbackUrl', 'fallbackLabel'];

const iniciarServidor = () =>
  new Promise(resolve => {
    const servidor = http.createServer((requisicao, resposta) => {
      const origem = `http://127.0.0.1:${servidor.address().port}`;
      const url = new URL(requisicao.url, origem);

      if (url.pathname === '/packs/js/sdk.js') {
        resposta.writeHead(200, {
          'Content-Type': 'application/javascript; charset=utf-8',
          'Cache-Control': 'no-store',
        });
        resposta.end(SDK_FALSO);
        return;
      }

      if (url.pathname === '/widget') {
        resposta.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        resposta.end(
          '<!doctype html><html lang="pt-BR"><title>Chat</title><h1>Chat em aba própria</h1>'
        );
        return;
      }

      if (url.pathname !== '/') {
        resposta.writeHead(404, {
          'Content-Type': 'text/plain; charset=utf-8',
        });
        resposta.end('not found');
        return;
      }

      const settings = {};
      CHAVES_DE_SETTINGS.forEach(chave => {
        const valor = url.searchParams.get(chave);
        if (valor) settings[chave] = valor;
      });

      resposta.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      resposta.end(paginaCom(origem, settings));
    });

    servidor.listen(0, '127.0.0.1', () => {
      resolve({
        origem: `http://127.0.0.1:${servidor.address().port}`,
        tokenDeTeste: TOKEN_DE_TESTE,
        fechar: () =>
          new Promise(pronto => {
            servidor.closeAllConnections();
            servidor.close(pronto);
          }),
      });
    });
  });

module.exports = { iniciarServidor, TOKEN_DE_TESTE };
