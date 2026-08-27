import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.TEST = 'true';

const { createServer: createViteServer } = await import('vite');
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

// Porta propria: as outras trilhas ocupam 3061 (aparencia), 3038/3999/8899
// (widget). `reuseExistingServer` fica FALSE na config exatamente para nao
// medir o worktree de outra sessao que por acaso tenha subido nesta porta.
const PORT = 3071;

const page = () => `<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Configuracao da caixa de entrada — harness</title>
    <script>
      window.globalConfig = { BRAND_NAME: 'ChatSPX', INSTALLATION_NAME: 'ChatSPX' };
      // O tema vem da querystring, para o teste medir contraste nos DOIS temas
      // sem depender do sistema operacional da maquina que roda a suite.
      (function () {
        var theme = new URLSearchParams(location.search).get('theme');
        if (theme === 'dark') document.documentElement.classList.add('dark');
      })();
    </script>
    <script type="module" src="/spec/e2e/inbox-config/harness/entry.js"></script>
  </head>
  <body class="h-full bg-n-background">
    <div id="app" class="h-full"></div>
  </body>
</html>`;

const vite = await createViteServer({
  root: repositoryRoot,
  configFile: path.join(repositoryRoot, 'vite.config.ts'),
  appType: 'custom',
  logLevel: 'warn',
  server: { hmr: { port: 4071 }, middlewareMode: true },
});

// Mesma razao do harness da aparencia: em middlewareMode o Vite compila sob
// demanda, entao sem aquecer o grafo o primeiro teste pagaria a compilacao
// inteira da `Settings.vue` (que puxa meia arvore de componentes) e estouraria
// os proprios limites.
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
    response.end(warmed ? 'inbox-config-ready' : 'inbox-config-warming');
    return;
  }
  if (url.pathname === '/inbox-config') {
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/html; charset=utf-8',
    });
    response.end(page());
    return;
  }
  vite.middlewares(request, response);
});

server.listen(PORT, '127.0.0.1', async () => {
  await warmModuleGraph('/spec/e2e/inbox-config/harness/entry.js');
  warmed = true;
});
