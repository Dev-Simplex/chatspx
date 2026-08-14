import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';

process.env.TEST = 'true';

const { createServer: createViteServer } = await import('vite');
const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');
const FROZEN_EPOCH = 1736942400;

const messages = [
  {
    id: 101,
    content: 'Olá, preciso de ajuda.',
    content_type: 'text',
    created_at: FROZEN_EPOCH - 240,
    message_type: 0,
    status: 'sent',
  },
  {
    id: 102,
    content: 'Mensagem determinística para o cenário.',
    content_type: 'text',
    created_at: FROZEN_EPOCH - 180,
    message_type: 1,
    status: 'sent',
    sender: {
      id: 7,
      name: 'Marina Lima',
      available_name: 'Marina Lima',
      availability_status: 'online',
    },
  },
  {
    id: 103,
    content: 'Vou conferir agora.',
    content_type: 'text',
    created_at: FROZEN_EPOCH - 120,
    message_type: 0,
    status: 'sent',
  },
  {
    id: 104,
    content: 'Resposta pendente número três.',
    content_type: 'text',
    created_at: FROZEN_EPOCH - 60,
    message_type: 1,
    status: 'sent',
    sender: {
      id: 7,
      name: 'Marina Lima',
      available_name: 'Marina Lima',
      availability_status: 'online',
    },
  },
];

const json = (response, body, status = 200) => {
  response.writeHead(status, {
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
  });
  response.end(JSON.stringify(body));
};

const widgetDocument = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ChatSPX widget E2E</title>
    <script>
      window.chatwootWebChannel = ${JSON.stringify({
        avatarUrl: '',
        hasAConnectedAgentBot: '',
        locale: 'pt_BR',
        websiteName: 'Equipe Simplex',
        websiteToken: 'widget-e2e-token',
        welcomeTagline: 'Atendimento humano, simples e direto.',
        welcomeTitle: 'Como podemos ajudar?',
        widgetColor: '#2DC46F',
        portal: null,
        enabledFeatures: [
          'attachments',
          'emoji_picker',
          'end_conversation',
          'use_inbox_avatar_for_bot',
        ],
        enabledLanguages: [
          { iso_639_1_code: 'pt_BR', name: 'Português (Brasil)' },
        ],
        replyTime: 'in_a_few_minutes',
        preChatFormEnabled: true,
        preChatFormOptions: {
          pre_chat_message: 'Conte um pouco sobre você.',
          pre_chat_fields: [
            {
              enabled: true,
              field_type: 'standard',
              label: 'Full name',
              name: 'fullName',
              placeholder: 'Full name',
              required: true,
              type: 'text',
            },
            {
              enabled: true,
              field_type: 'standard',
              label: 'Email',
              name: 'emailAddress',
              placeholder: 'name@example.com',
              required: true,
              type: 'email',
            },
          ],
        },
        workingHoursEnabled: false,
        csatSurveyEnabled: true,
        workingHours: [],
        outOfOfficeMessage: '',
        utcOffset: '+00:00',
        timezone: 'UTC',
        allowMessagesAfterResolved: true,
        disableBranding: true,
      })};
      window.chatwootPubsubToken = 'widget-e2e-pubsub';
      window.authToken = 'widget-e2e-auth';
      window.globalConfig = ${JSON.stringify({
        BRAND_NAME: 'ChatSPX',
        DIRECT_UPLOADS_ENABLED: false,
        INSTALLATION_NAME: 'ChatSPX',
        MAXIMUM_FILE_UPLOAD_SIZE: 40,
      })};
    </script>
    <script type="module" src="/app/javascript/entrypoints/widget.js"></script>
  </head>
  <body>
    <div id="app" class="h-full"></div>
  </body>
</html>`;

const handleApi = (request, response, url) => {
  if (request.method === 'GET' && url.pathname === '/api/v1/widget/messages') {
    json(response, {
      payload: messages,
      meta: { contact_last_seen_at: FROZEN_EPOCH - 210 },
    });
    return true;
  }
  if (
    request.method === 'GET' &&
    url.pathname === '/api/v1/widget/inbox_members'
  ) {
    json(response, {
      payload: [
        {
          id: 7,
          name: 'Marina Lima',
          availability_status: 'online',
        },
      ],
    });
    return true;
  }
  if (request.method === 'GET' && url.pathname === '/api/v1/widget/contact') {
    json(response, { id: 19, name: 'Visitante E2E' });
    return true;
  }
  if (
    request.method === 'GET' &&
    url.pathname === '/api/v1/widget/conversations'
  ) {
    json(response, {
      id: 31,
      status: 'open',
      contact_last_seen_at: FROZEN_EPOCH - 210,
    });
    return true;
  }
  if (request.method === 'GET' && url.pathname === '/api/v1/widget/campaigns') {
    json(response, []);
    return true;
  }
  if (
    request.method === 'POST' &&
    [
      '/api/v1/widget/events',
      '/api/v1/widget/conversations/update_last_seen',
    ].includes(url.pathname)
  ) {
    json(response, {});
    return true;
  }
  return false;
};

const vite = await createViteServer({
  root: repositoryRoot,
  configFile: path.join(repositoryRoot, 'vite.config.ts'),
  appType: 'custom',
  logLevel: 'warn',
  server: {
    hmr: { port: 4001 },
    middlewareMode: true,
  },
});

const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1:3999');
  if (url.pathname === '/__ready') {
    response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('widget-ready');
    return;
  }
  if (url.pathname === '/widget') {
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/html; charset=utf-8',
    });
    response.end(widgetDocument);
    return;
  }
  if (url.pathname.startsWith('/api/v1/widget/')) {
    if (!handleApi(request, response, url)) {
      json(
        response,
        {
          error: `Unhandled widget E2E route: ${request.method} ${url.pathname}`,
        },
        500
      );
    }
    return;
  }
  vite.middlewares(request, response);
});

const webSocketServer = new WebSocketServer({ noServer: true });
webSocketServer.on('connection', socket => {
  socket.send(JSON.stringify({ type: 'welcome' }));
  socket.on('message', rawMessage => {
    const message = JSON.parse(rawMessage.toString());
    if (message.command === 'subscribe') {
      socket.send(
        JSON.stringify({
          type: 'confirm_subscription',
          identifier: message.identifier,
        })
      );
    }
  });
});
server.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url, 'http://127.0.0.1:3999');
  if (url.pathname !== '/cable') {
    socket.destroy();
    return;
  }
  webSocketServer.handleUpgrade(request, socket, head, webSocket => {
    webSocketServer.emit('connection', webSocket, request);
  });
});

const close = async () => {
  await vite.close();
  webSocketServer.close();
  server.close();
};

process.once('SIGINT', close);
process.once('SIGTERM', close);
server.listen(3999, '127.0.0.1');
