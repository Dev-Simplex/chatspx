import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.TEST = 'true';

const { createServer: createViteServer } = await import('vite');
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

/**
 * Porta configurável por `TRIGGERS_PORT`. O default continua 3062, então nada
 * muda para quem roda de um checkout só. A variável existe porque este arquivo
 * calcula `repositoryRoot` a partir do próprio caminho: um servidor de OUTRA
 * worktree que já esteja com a porta serve o código DELA, e o
 * `reuseExistingServer` da config o adotaria em silêncio — a suíte ficaria
 * medindo a árvore errada sem uma linha de aviso.
 */
const PORT = Number(process.env.TRIGGERS_PORT || 3062);

const page = theme => `<!doctype html>
<html lang="pt-BR"${theme === 'dark' ? ' class="dark"' : ''}>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tela de gatilhos — harness</title>
    <script>
      window.globalConfig = { BRAND_NAME: 'ChatSPX', INSTALLATION_NAME: 'ChatSPX' };
    </script>
    <script type="module" src="/spec/e2e/triggers/harness/entry.js"></script>
  </head>
  <body class="h-full">
    <div id="app" class="h-full"></div>
  </body>
</html>`;

const vite = await createViteServer({
  root: repositoryRoot,
  configFile: path.join(repositoryRoot, 'vite.config.ts'),
  appType: 'custom',
  logLevel: 'warn',
  server: { hmr: { port: PORT + 1000 }, middlewareMode: true },
});

// Mesma razão do harness do widget: o Vite em middlewareMode compila sob
// demanda, então sem aquecer o grafo o primeiro teste pagaria a compilação
// inteira e estouraria os próprios limites.
const warmModuleGraph = async entryUrl => {
  const visited = new Set();
  const visit = async url => {
    if (!url || visited.has(url)) return;
    visited.add(url);
    try {
      await vite.transformRequest(url);
    } catch {
      return;
    }
    const node = await vite.moduleGraph.getModuleByUrl(url);
    if (!node) return;
    await Promise.all([...node.importedModules].map(child => visit(child.url)));
  };
  await visit(entryUrl);
};

let warmed = false;

const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname === '/__ready') {
    response.writeHead(warmed ? 200 : 503, {
      'Content-Type': 'text/plain; charset=utf-8',
    });
    // Diz QUAL árvore este servidor serve: é o único jeito de conferir, de
    // fora, que a porta não pertence a outra worktree.
    response.end(
      `${warmed ? 'triggers-ready' : 'triggers-warming'} ${repositoryRoot}`
    );
    return;
  }
  if (url.pathname === '/triggers') {
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/html; charset=utf-8',
    });
    response.end(page(url.searchParams.get('theme')));
    return;
  }
  vite.middlewares(request, response);
});

server.listen(PORT, '127.0.0.1', async () => {
  await warmModuleGraph('/spec/e2e/triggers/harness/entry.js');
  warmed = true;
});
