/**
 * Servidor do aceite do 4.03. Sobe o Vite em `middlewareMode` numa porta
 * EFÊMERA (porta 0, atribuída pelo sistema) — de propósito: as portas fixas do
 * harness do widget (3038/3999/8899) são recurso disputado por várias trilhas, e
 * este teste não precisa de nenhuma delas. Sem porta fixa não há corrida.
 */
// `TEST=true` REMOVE o RubyPlugin do `vite.config.ts`. Sem isso o plugin reescreve
// o `root` para `app/javascript` e todo caminho fora dele — inclusive este
// `spec/e2e/...` — devolve 404. Precisa ser setado ANTES de o config ser lido.
process.env.TEST = 'true';

import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WATCH_IGNORADO } from '../harness/watch-ignore.mjs';
import { portaHmrLivre } from '../harness/porta-hmr.mjs';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

const documento = `<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>4.03 — captura em 375 px</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/@vite/client"></script>
    <script type="module" src="/spec/e2e/widget/capture/mount.js"></script>
  </body>
</html>`;

export const iniciar = async () => {
  const { createServer: createViteServer } = await import('vite');
  const vite = await createViteServer({
    root: repositoryRoot,
    configFile: path.join(repositoryRoot, 'vite.config.ts'),
    appType: 'custom',
    logLevel: 'warn',
    // `watch.ignored` pela mesma razão dos harness de `harness/`: `root` é o
    // repositório inteiro, e sem a lista o chokidar gasta um watch de inotify
    // por diretório da árvore toda. Ver `../harness/watch-ignore.mjs`.
    server: {
      // `hmr: false` NÃO desliga o socket: o Vite cai no default 24678 e os
      // dois harness auxiliares do projeto `widget` brigam por ele. Ver
      // `../harness/porta-hmr.mjs`.
      hmr: { port: await portaHmrLivre() },
      middlewareMode: true,
      watch: { ignored: WATCH_IGNORADO },
    },
  });

  const servidor = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname === '/' || url.pathname === '/captura') {
      response.writeHead(200, {
        'Cache-Control': 'no-store',
        'Content-Type': 'text/html; charset=utf-8',
      });
      response.end(documento);
      return;
    }
    vite.middlewares(request, response);
  });

  // AQUECIMENTO DIRIGIDO — e a palavra "dirigido" custou uma medicao para chegar aqui.
  //
  // A primeira versao aquecia o grafo INTEIRO, andando por `importedModules` a partir do
  // mount. Medido em 18/08/2026: **3.863 modulos e 235 s**, contra os 120 s de teto do
  // projeto `widget` no Playwright — e o `beforeAll` estourava.
  //
  // A causa nao era o `createViteServer` (7,9 s dos 235) nem o `App.vue`: tirar o App.vue
  // nao mudou UM modulo. O que explodia era o proprio `importedModules` do CSS — o Vite
  // registra como dependencia do modulo de estilo TODO arquivo que o `content` do Tailwind
  // varre, e a quebra por diretorio mostrou 2.621 modulos de `dashboard/` e dezenas de
  // `.erb` de `app/views/**`. Andar por essas arestas era percorrer o projeto inteiro para
  // medir a largura de um formulario.
  //
  // Aqui aquecemos so o que o navegador de fato pede primeiro: o modulo de entrada e o CSS.
  // O resto o Vite transforma sob demanda, que e barato porque o grafo JS desta pagina tem
  // dezenas de modulos, nao milhares.
  await Promise.all(
    [
      '/spec/e2e/widget/capture/mount.js',
      '/app/javascript/widget/wootStyles.harness.scss',
    ].map(url => vite.transformRequest(url).catch(() => null))
  );

  await new Promise(resolve => {
    servidor.listen(0, '127.0.0.1', resolve);
  });
  const { port } = servidor.address();

  return {
    url: `http://127.0.0.1:${port}/captura`,
    encerrar: async () => {
      await new Promise(resolve => {
        servidor.close(resolve);
      });
      await vite.close();
    },
  };
};
