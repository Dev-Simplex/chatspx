import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.TEST = 'true';

const { createServer: createViteServer } = await import('vite');
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

const vite = await createViteServer({
  root: repositoryRoot,
  configFile: path.join(repositoryRoot, 'vite.config.ts'),
  appType: 'custom',
  logLevel: 'warn',
  server: {
    hmr: { port: 3040 },
    middlewareMode: true,
  },
});

// O Vite em middlewareMode transforma sob demanda e não persiste esse cache em
// disco, então o PRIMEIRO teste pagaria sozinho a compilação do grafo inteiro
// (~45s medidos) e estouraria os próprios limites (page.goto 15s, poll 30s).
// Aquecemos o grafo antes de anunciar prontidão: esse custo pertence ao boot do
// `webServer` (timeout no playwright.config.js), não ao primeiro teste.
const warmModuleGraph = async entryUrl => {
  const visited = new Set();
  const visit = async url => {
    if (!url || visited.has(url)) return;
    visited.add(url);
    try {
      await vite.transformRequest(url);
    } catch {
      // Módulo não transformável (asset estático, dependência externa) não
      // bloqueia o aquecimento — o browser também o buscaria sem transformar.
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
  response.setHeader('Access-Control-Allow-Origin', '*');
  if (request.url === '/__ready') {
    const status = warmed ? 200 : 503;
    response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(warmed ? 'sdk-ready' : 'sdk-warming');
    return;
  }
  vite.middlewares(request, response);
});

// Registrar um handler de SIGINT/SIGTERM cancela o encerramento default do
// processo, e `server.close()` sozinho não derruba as conexões keep-alive que o
// browser deixou abertas — o processo sobrevivia à suíte e a execução SEGUINTE
// morria com "http://127.0.0.1:3038/__ready is already used".
const close = async () => {
  server.closeAllConnections();
  await vite.close().catch(() => {});
  server.close();
  process.exit(0);
};

process.once('SIGINT', close);
process.once('SIGTERM', close);
server.listen(3038, '127.0.0.1', () => {
  warmModuleGraph('/app/javascript/entrypoints/sdk.js').then(() => {
    warmed = true;
  });
});
