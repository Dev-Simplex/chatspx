/**
 * Harness do bloco 2.13 — telemetria de erro do widget.
 *
 * A pergunta que este harness responde é a segunda metade do aceite: «nada vaza
 * para o `window.onerror` do site do cliente». Isso é uma afirmação sobre a
 * FRONTEIRA entre dois documentos, e nenhum teste de unidade a alcança: em
 * jsdom não há iframe de verdade, não há propagação de erro entre documentos e
 * não há `unhandledrejection` real.
 *
 * A montagem imita a de produção:
 *   · página PAI   = o site do cliente, com `window.onerror` e
 *                    `unhandledrejection` instalados e acumulando em um array
 *   · página FILHA = o documento do widget, dentro de um `<iframe>`
 *   · `/api/v1/widget/telemetry` = o endpoint real, que aqui só registra o que
 *                    recebeu, para o teste inspecionar o corpo
 *
 * O módulo servido à filha é o `widget/helpers/telemetry.js` DE VERDADE,
 * empacotado pelo esbuild em tempo de execução. Não há cópia, não há artefato
 * commitado e não há passo manual de regeneração — se o módulo mudar, o teste
 * roda o novo automaticamente.
 *
 * Porta EFÊMERA (`listen(0)`) e servidor dentro do processo do teste: não
 * encosta no harness de porta fixa do widget (3038/3999/8899).
 */
const http = require('node:http');
const path = require('node:path');

const RAIZ = path.resolve(__dirname, '..', '..', '..', '..');
const ESBUILD = path.join(
  RAIZ,
  'node_modules/.pnpm/esbuild@0.25.12/node_modules/esbuild'
);
const MODULO = path.join(RAIZ, 'app/javascript/widget/helpers/telemetry.js');

const empacotarTelemetria = async () => {
  // eslint-disable-next-line global-require
  const esbuild = require(ESBUILD);
  const resultado = await esbuild.build({
    entryPoints: [MODULO],
    bundle: true,
    format: 'iife',
    globalName: 'Telemetria',
    write: false,
    target: 'es2020',
  });
  return resultado.outputFiles[0].text;
};

const PAGINA_PAI = `<!doctype html>
<html lang="pt-BR">
  <head><meta charset="utf-8"><title>Site do cliente</title></head>
  <body>
    <h1>Loja do cliente</h1>
    <script>
      // O que o site do cliente enxergaria. Se algo do widget vazar, cai aqui.
      window.vazamentos = [];
      window.onerror = function (mensagem) {
        window.vazamentos.push({ tipo: 'onerror', mensagem: String(mensagem) });
        return false;
      };
      window.addEventListener('unhandledrejection', function (evento) {
        window.vazamentos.push({
          tipo: 'unhandledrejection',
          mensagem: String(evento.reason && evento.reason.message),
        });
      });
    </script>
    <iframe id="widget" src="/widget" style="width:400px;height:560px"></iframe>
  </body>
</html>`;

const paginaFilha = bundle => `<!doctype html>
<html lang="pt-BR">
  <head><meta charset="utf-8"><title>Widget</title></head>
  <body>
    <div id="app">painel</div>
    <script>
      window.chatwootWebChannel = { websiteToken: 'token-e2e-2-13', release: 'v-teste' };
    </script>
    <script>${bundle}</script>
  </body>
</html>`;

const iniciarServidor = async () => {
  const bundle = await empacotarTelemetria();
  const recebidos = [];

  return new Promise(resolve => {
    const servidor = http.createServer((requisicao, resposta) => {
      const origem = `http://127.0.0.1:${servidor.address().port}`;
      const url = new URL(requisicao.url, origem);

      if (url.pathname === '/api/v1/widget/telemetry') {
        let corpo = '';
        requisicao.on('data', pedaco => {
          corpo += pedaco;
        });
        requisicao.on('end', () => {
          try {
            recebidos.push(JSON.parse(corpo));
          } catch {
            recebidos.push({ corpoInvalido: corpo });
          }
          resposta.writeHead(204);
          resposta.end();
        });
        return;
      }

      if (url.pathname === '/widget') {
        resposta.writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        });
        resposta.end(paginaFilha(bundle));
        return;
      }

      if (url.pathname !== '/') {
        resposta.writeHead(404, {
          'Content-Type': 'text/plain; charset=utf-8',
        });
        resposta.end('not found');
        return;
      }

      resposta.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      resposta.end(PAGINA_PAI);
    });

    servidor.listen(0, '127.0.0.1', () => {
      resolve({
        origem: `http://127.0.0.1:${servidor.address().port}`,
        recebidos,
        limparRecebidos: () => recebidos.splice(0, recebidos.length),
        fechar: () =>
          new Promise(pronto => {
            servidor.closeAllConnections();
            servidor.close(pronto);
          }),
      });
    });
  });
};

module.exports = { iniciarServidor };
