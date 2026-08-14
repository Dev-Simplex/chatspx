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

const server = http.createServer((request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  if (request.url === '/__ready') {
    response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('sdk-ready');
    return;
  }
  vite.middlewares(request, response);
});

const close = async () => {
  await vite.close();
  server.close();
};

process.once('SIGINT', close);
process.once('SIGTERM', close);
server.listen(3038, '127.0.0.1');
