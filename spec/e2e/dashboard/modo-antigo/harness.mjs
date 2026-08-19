/**
 * Servidor do aceite de APARÊNCIA do bloco 4.22 (a seção "modo antigo").
 *
 * Mesma mecânica do harness do 4.03 e do 6.03: Vite em `middlewareMode` numa porta
 * EFÊMERA. As portas fixas 3038/3999/8899 são slot único sob tranca do coordenador —
 * e, além disso, elas servem o WIDGET. Esta seção é do PAINEL, então nem faria
 * sentido pedi-las.
 */
process.env.TEST = 'true';

import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

const documento = `<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>4.22 — modo antigo</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/@vite/client"></script>
    <script type="module" src="/spec/e2e/dashboard/modo-antigo/mount.js"></script>
  </body>
</html>`;

export const iniciar = async () => {
  const { createServer: createViteServer } = await import('vite');
  const vite = await createViteServer({
    root: repositoryRoot,
    configFile: path.join(repositoryRoot, 'vite.config.ts'),
    appType: 'custom',
    logLevel: 'warn',
    server: { hmr: false, middlewareMode: true },
  });

  const servidor = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname === '/' || url.pathname === '/modo-antigo') {
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
  // (andar pelo grafo inteiro custa milhares de módulos) está no harness do 4.03.
  await Promise.all(
    [
      '/spec/e2e/dashboard/modo-antigo/mount.js',
      '/app/javascript/dashboard/assets/scss/app.scss',
    ].map(url => vite.transformRequest(url).catch(() => null))
  );

  await new Promise(resolve => {
    servidor.listen(0, '127.0.0.1', resolve);
  });
  const { port } = servidor.address();

  return {
    url: `http://127.0.0.1:${port}/modo-antigo`,
    encerrar: async () => {
      await new Promise(resolve => {
        servidor.close(resolve);
      });
      await vite.close();
    },
  };
};
