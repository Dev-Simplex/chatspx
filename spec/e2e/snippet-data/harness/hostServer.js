/**
 * Harness do bloco 5.18 — `data-*` de configuração no snippet.
 *
 * O QUE ELE MEDE, e por que precisa de navegador. O diagnóstico deste bloco não era uma regra
 * errada: era `document.currentScript` valer `null` dentro de `g.onload`. Isso é comportamento
 * de especificação do navegador, e é exatamente o tipo de coisa que um dublê em jsdom pode
 * fabricar sem querer — bastava o teste montar a tag e chamar `run()` de forma síncrona para o
 * defeito sumir. Aqui o snippet é o REAL (o mesmo arquivo que
 * `spec/models/channel/web_widget_fallback_snippet_spec.rb` prova ser byte a byte o que o
 * servidor gera) e o `sdk.js` é o REAL (`public/packs/js/sdk.js`, saído de
 * `vite build --config vite.lib.config.ts`).
 *
 * PORTA EFÊMERA E SERVIDOR NO PRÓPRIO PROCESSO, pela mesma razão do harness do 2.14: o harness
 * de porta fixa do widget (3038/3999/8899) é slot único disputado por várias trilhas, e uma
 * corrida que "confere e entra" perde para outra.
 *
 * `SNIPPET_B518` e `SDK_B518` existem para o VERMELHO ANTES DO VERDE: apontando-os para os
 * artefatos gerados a partir de 9ab1588a36 (o snippet sem marcador e o `sdk.js` que lia dentro
 * do `onload`), a mesma suíte roda contra o estado anterior e falha. Sem isso, "a configuração
 * chega" seria uma asserção que nunca viu o mundo em que ela não chegava.
 */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const RAIZ = path.resolve(__dirname, '..', '..', '..', '..');

const CAMINHO_DO_SNIPPET =
  process.env.SNIPPET_B518 ||
  path.join(RAIZ, 'spec', 'e2e', 'fallback', 'fixtures', 'snippet.html');

const CAMINHO_DO_SDK =
  process.env.SDK_B518 || path.join(RAIZ, 'public', 'packs', 'js', 'sdk.js');

const TOKEN_DE_TESTE = 'token-de-teste-5-18';

// A tag do snippet, do jeito que o servidor a escreve. É por ESTE texto que o harness encontra
// onde pendurar os `data-*` — e o teste confere que a injeção aconteceu, senão um harness que
// não achou a tag serviria uma página sem atributo nenhum e o exemplo passaria medindo o vazio.
const TAG_DO_SNIPPET = '<script data-chatspx-snippet>';

const lerSnippet = () => fs.readFileSync(CAMINHO_DO_SNIPPET, 'utf-8');

const lerSdk = () => {
  if (!fs.existsSync(CAMINHO_DO_SDK)) {
    throw new Error(
      `sdk.js não existe em ${CAMINHO_DO_SDK}. Gere-o com: pnpm build:sdk`
    );
  }

  return fs.readFileSync(CAMINHO_DO_SDK, 'utf-8');
};

// `data-hide-message-bubble` a partir de `hideMessageBubble`: é a conversão que o navegador faz
// no sentido inverso ao montar o `dataset`, e escrevê-la aqui é o que torna o teste uma medida
// do caminho real (o integrador digita o atributo com hífen, não a chave camelCase).
const paraAtributo = chave =>
  `data-${chave.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()}`;

const escapar = valor =>
  String(valor)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;');

const paginaCom = (
  origem,
  { dataset = {}, settings = null, remover = false }
) => {
  const bruto = lerSnippet();

  const atributos = Object.entries(dataset)
    .map(([chave, valor]) => `${paraAtributo(chave)}="${escapar(valor)}"`)
    .join(' ');

  const comAtributos = atributos
    ? bruto.replace(
        TAG_DO_SNIPPET,
        `<script data-chatspx-snippet ${atributos}>`
      )
    : bruto;

  const snippet = comAtributos
    .split('__BASE_URL__')
    .join(origem)
    .split('__WEBSITE_TOKEN__')
    .join(TOKEN_DE_TESTE);

  const linhaDeSettings = settings
    ? `<script>window.chatwootSettings = ${JSON.stringify(settings)};</script>`
    : '';

  // `remover` reproduz o gerenciador de tag / CMS que injeta o snippet e limpa o nó em seguida.
  // É SÍNCRONO e vem logo depois da tag de propósito: `sdk.js` é `async`, então neste instante
  // ele nem começou a baixar — quando o `onload` chegar, a tag não existirá mais. Um
  // `MutationObserver` daria a mesma ideia com corrida no meio, e corrida em teste é falso verde
  // esperando a vez.
  const linhaDeRemocao = remover
    ? `<script>document.querySelector('script[data-chatspx-snippet]').remove();</script>`
    : '';

  return `<!doctype html>
<html lang="pt-BR">
  <head><meta charset="utf-8"><title>Site do cliente</title></head>
  <body>
    <main><h1>Loja do cliente</h1></main>
    ${linhaDeSettings}
${snippet}
    ${linhaDeRemocao}
  </body>
</html>`;
};

const iniciarServidor = () =>
  new Promise(resolve => {
    const servidor = http.createServer((requisicao, resposta) => {
      const origem = `http://127.0.0.1:${servidor.address().port}`;
      const url = new URL(requisicao.url, origem);

      // O bundle que NÃO chega (bloqueador de conteúdo, CSP do site) — o caminho em que o link
      // alternativo do 2.14 nasce — é reproduzido pelo próprio teste, com `page.route(...).abort()`:
      // é o navegador recusando a requisição, não o servidor respondendo 404, e é o mais próximo
      // do que um bloqueador faz.
      if (url.pathname === '/packs/js/sdk.js') {
        resposta.writeHead(200, {
          'Content-Type': 'application/javascript; charset=utf-8',
          'Cache-Control': 'no-store',
        });
        resposta.end(lerSdk());
        return;
      }

      if (url.pathname === '/widget') {
        resposta.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        resposta.end(
          '<!doctype html><html lang="pt-BR"><title>Chat</title><h1>Painel do widget</h1>'
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

      const dataset = JSON.parse(url.searchParams.get('dataset') || '{}');
      const settings = url.searchParams.get('settings')
        ? JSON.parse(url.searchParams.get('settings'))
        : null;
      const remover = url.searchParams.get('remover') === '1';

      resposta.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      resposta.end(paginaCom(origem, { dataset, settings, remover }));
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

module.exports = {
  iniciarServidor,
  TOKEN_DE_TESTE,
  TAG_DO_SNIPPET,
  CAMINHO_DO_SNIPPET,
  CAMINHO_DO_SDK,
};
