import http from 'node:http';

const SDK_URL = 'http://127.0.0.1:3038';
const WIDGET_URL = 'http://127.0.0.1:3999';
const allowedScenarios = new Set([
  // `rich-types` reusa a rota de mensagens; o que o distingue são as mensagens
  // dos sete content_type ricos, injetadas no store pelo spec.
  'rich-types',
  'home',
  'messages',
  'prechat-form',
  'unread',
]);
// `auto` é o cenário do bloco 2.10: o cliente NÃO escreveu `darkMode` no
// snippet. Não é um terceiro tema — é a AUSÊNCIA de configuração, que é
// justamente o que o aceite mede ("sem `darkMode` configurado e SO escuro").
// Os 16 snapshots continuam saindo de `light`/`dark`, e a matriz de
// `widget.spec.js` não muda.
const allowedThemes = new Set(['light', 'dark', 'auto']);

const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1:8899');
  if (url.pathname === '/__ready') {
    response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('host-ready');
    return;
  }
  if (url.pathname === '/__sabotage__/500') {
    response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('sabotage');
    return;
  }
  if (url.pathname !== '/') {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('not found');
    return;
  }

  const requestedScenario = url.searchParams.get('scenario') || 'home';
  const requestedTheme = url.searchParams.get('theme') || 'light';
  const scenario = allowedScenarios.has(requestedScenario)
    ? requestedScenario
    : 'home';
  const theme = allowedThemes.has(requestedTheme) ? requestedTheme : 'light';
  const settings = {
    availableMessage: 'Estamos conectados.',
    enableEmojiPicker: true,
    enableEndConversation: true,
    enableFileUpload: true,
    locale: 'pt_BR',
    showUnreadMessagesDialog: scenario === 'unread',
    unavailableMessage: 'Voltaremos em breve.',
    welcomeDescription: 'Atendimento humano, simples e direto.',
    welcomeTitle: 'Como podemos ajudar?',
  };

  // A chave só existe quando o cliente a configurou. Mandar `darkMode:
  // undefined` não serviria: o `config-set` viaja por `postMessage`, que
  // descarta `undefined` na serialização, mas o SDK ainda passaria pelo
  // `getDarkMode` como se houvesse escolha. Aqui a ausência é ausência.
  if (theme !== 'auto') {
    settings.darkMode = theme;
  }

  response.writeHead(200, {
    'Cache-Control': 'no-store',
    'Content-Type': 'text/html; charset=utf-8',
  });
  response.end(`<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="${theme === 'auto' ? 'light dark' : theme}">
    <title>Host real do widget</title>
  </head>
  <body>
    <main aria-label="Página hospedeira determinística">
      <h1>Atendimento Simplex</h1>
      <p>Chassi real do SDK carregado após o conteúdo da página.</p>
    </main>
    <script>
      window.__WIDGET_E2E_SCENARIO__ = ${JSON.stringify(scenario)};
      window.chatwootSettings = ${JSON.stringify(settings)};
    </script>
    <script id="chatwoot-snippet" type="module">
      import '${SDK_URL}/app/javascript/entrypoints/sdk.js';
      window.chatwootSDK.run({
        baseUrl: '${WIDGET_URL}',
        websiteToken: 'widget-e2e-token'
      });
    </script>
  </body>
</html>`);
});

// Mesmo motivo dos servidores Vite: o handler cancela o encerramento default e
// `server.close()` não derruba as conexões keep-alive, deixando a porta 8899
// presa para a execução seguinte da suíte.
const close = () => {
  server.closeAllConnections();
  server.close();
  process.exit(0);
};

process.once('SIGINT', close);
process.once('SIGTERM', close);
server.listen(8899, '127.0.0.1');
