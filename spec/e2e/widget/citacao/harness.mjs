/**
 * Servidor do aceite de APARÊNCIA do bloco 6.03 (citação de fonte).
 *
 * Mesma mecânica do harness do 4.03 (`spec/e2e/widget/capture/harness.mjs`), e pela
 * mesma razão: Vite em `middlewareMode` numa porta EFÊMERA (porta 0, atribuída pelo
 * sistema). As portas fixas do harness do widget (3038/3999/8899) são slot único sob
 * tranca do coordenador, e medir a cor de um rodapé não precisa de nenhuma delas.
 */
// `TEST=true` REMOVE o RubyPlugin do `vite.config.ts`. Sem isso o plugin reescreve o
// `root` para `app/javascript` e todo caminho fora dele — inclusive este `spec/e2e/...`
// — devolve 404. Precisa ser setado ANTES de o config ser lido.
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
    <title>6.03 — citação de fonte</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/@vite/client"></script>
    <script type="module" src="/spec/e2e/widget/citacao/mount.js"></script>
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
    if (url.pathname === '/' || url.pathname === '/citacao') {
      response.writeHead(200, {
        'Cache-Control': 'no-store',
        'Content-Type': 'text/html; charset=utf-8',
      });
      response.end(documento);
      return;
    }
    vite.middlewares(request, response);
  });

  // Aquecimento DIRIGIDO — só o módulo de entrada e o CSS. A procedência do número
  // (3.863 módulos / 235 s ao andar pelo grafo inteiro) está no harness do 4.03; a
  // causa é o `importedModules` do CSS registrar tudo que o `content` do Tailwind
  // varre. Aqui o resto o Vite transforma sob demanda.
  await Promise.all(
    [
      '/spec/e2e/widget/citacao/mount.js',
      '/app/javascript/widget/wootStyles.harness.scss',
    ].map(url => vite.transformRequest(url).catch(() => null))
  );

  await new Promise(resolve => {
    servidor.listen(0, '127.0.0.1', resolve);
  });
  const { port } = servidor.address();

  return {
    url: `http://127.0.0.1:${port}/citacao`,
    encerrar: async () => {
      await new Promise(resolve => {
        servidor.close(resolve);
      });
      await vite.close();
    },
  };
};
