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
    server: { hmr: false, middlewareMode: true },
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

  // O Vite em middlewareMode transforma sob demanda. Sem aquecer, o PRIMEIRO
  // `page.goto` paga sozinho a compilação do grafo inteiro do widget (dezenas de
  // segundos) e estoura o timeout de navegação — o custo pertence ao boot, não à
  // medição. Mesmo procedimento do harness oficial (`harness/widget-server.mjs`).
  const aquecer = async entrada => {
    const visitados = new Set();
    const visitar = async url => {
      if (!url || visitados.has(url)) return;
      visitados.add(url);
      try {
        await vite.transformRequest(url);
      } catch {
        return; // asset estático / dependência externa: o browser também não transformaria
      }
      const no = await vite.moduleGraph.getModuleByUrl(url);
      if (!no) return;
      await Promise.all([...no.importedModules].map(filho => visitar(filho.url)));
    };
    await visitar(entrada);
  };
  await aquecer('/spec/e2e/widget/capture/mount.js');

  await new Promise(resolve => servidor.listen(0, '127.0.0.1', resolve));
  const { port } = servidor.address();

  return {
    url: `http://127.0.0.1:${port}/captura`,
    encerrar: async () => {
      await new Promise(resolve => servidor.close(resolve));
      await vite.close();
    },
  };
};
