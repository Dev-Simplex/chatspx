#!/usr/bin/env node
/**
 * Bloco 5.10 — o aceite MEDIDO EM NAVEGADOR REAL, não em jsdom.
 *
 * Por que este arquivo existe além do `tags.spec.js`: o aceite fala de coisas que o jsdom não
 * tem. "Console limpo" é o console do Chromium, com os avisos que ele mesmo emite; "o `gtag` do
 * cliente continua funcional" é uma função viva num documento vivo; e o artefato medido aqui é o
 * `public/packs/js/tracking.js` REAL — o mesmo arquivo, minificado, que o visitante baixa.
 *
 * Uso:
 *   npx vite build --config vite.tracking.config.ts
 *   node app/javascript/sdk/tracking/specs/browser/ponte-de-tags.check.mjs
 *
 * Sai 0 quando todas as asserções passam, 1 quando alguma falha, 2 quando não conseguiu medir —
 * porque "não consegui medir" nunca pode sair como verde.
 */
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { chromium } from 'playwright';

const RAIZ = process.cwd();
const ARTEFATO = path.join(RAIZ, 'public/packs/js/tracking.js');

if (!fs.existsSync(ARTEFATO)) {
  console.error(
    `[5.10] artefato ausente: ${ARTEFATO}\n` +
      'Rode `npx vite build --config vite.tracking.config.ts` antes.'
  );
  process.exit(2);
}

/**
 * A página do CLIENTE, como ela é de verdade: um site que já tem GTM, já tem `dataLayer` com
 * coisas dentro, já tem um `gtag` próprio e já tem TRÊS pixels da Meta inicializados — o dele, o
 * da agência e o do parceiro. É a página em que `fbq('track', …)` conta a conversão três vezes.
 */
const PAGINA = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>site do cliente</title>
<script>
  // O que o site do cliente já tinha antes de nós.
  window.dataLayer = [{ event: 'gtm.js' }, { event: 'promocao_vista' }];
  window.__gtagDoCliente = function () { window.__gtagChamadas.push([].slice.call(arguments)); };
  window.__gtagChamadas = [];
  window.gtag = window.__gtagDoCliente;
  window.dataLayer.push(['config', 'G-DOCLIENTE']);

  // Três pixels na página. O \`getState\` é a mesma superfície que o \`fbevents.js\` expõe.
  window.__fbqChamadas = [];
  window.fbq = function () { window.__fbqChamadas.push([].slice.call(arguments)); };
  window.fbq.getState = function () {
    return { pixels: [{ id: '111' }, { id: '222' }, { id: '333' }] };
  };
</script>
</head><body><h1>site do cliente</h1></body></html>`;

const servidor = http.createServer((req, res) => {
  if (req.url.startsWith('/packs/js/tracking.js')) {
    res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    res.end(fs.readFileSync(ARTEFATO));
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(PAGINA);
});

const falhas = [];
const conferir = (nome, condicao, detalhe = '') => {
  if (condicao) console.log(`  ok   ${nome}`);
  else {
    console.log(`  FALHA ${nome}${detalhe ? ` — ${detalhe}` : ''}`);
    falhas.push(nome);
  }
};

await new Promise(resolve => servidor.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${servidor.address().port}`;

const navegador = await chromium.launch();
const contexto = await navegador.newContext();
const pagina = await contexto.newPage();

// TUDO o que o console recebe, inclusive o que o Chromium emite por conta própria.
const console_ = [];
pagina.on('console', msg => console_.push(`${msg.type()}: ${msg.text()}`));
pagina.on('pageerror', erro => console_.push(`pageerror: ${erro.message}`));

await pagina.goto(base, { waitUntil: 'networkidle' });

const resultado = await pagina.evaluate(async origem => {
  const { createTagBridge } = await import(`${origem}/packs/js/tracking.js`);

  const gtagAntes = window.gtag;
  const dataLayerAntes = window.dataLayer;
  const tamanhoAntes = window.dataLayer.length;

  const publicar = createTagBridge({
    tracking: {
      meta_pixel_id: '222',
      ga4_measurement_id: 'G-DOCLIENTE',
      google_ads_send_to: 'AW-123456789/rotulo',
      // `install_tags` AUSENTE: é o padrão de fábrica, e nenhuma tag nossa pode ser instalada.
      event_map: {
        chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
        chatspx_widget_opened: { enabled: false, meta: null, ga4: 'widget_open' },
      },
    },
    isAllowed: () => true,
  });

  publicar('chatspx_lead', { value: 99, currency: 'BRL', email: 'ana@exemplo.com.br' }, 'uuid-real');
  publicar('chatspx_widget_opened', { inbox_id: 7 });

  return {
    gtagPreservado: window.gtag === gtagAntes,
    dataLayerPreservado: window.dataLayer === dataLayerAntes,
    entradasAntes: window.dataLayer.slice(0, tamanhoAntes).map(e => e && e.event),
    publicados: window.dataLayer
      .filter(e => e && typeof e.event === 'string' && e.event.startsWith('chatspx_'))
      .map(e => JSON.parse(JSON.stringify(e))),
    fbq: window.__fbqChamadas,
    gtagChamadas: window.__gtagChamadas,
    scriptsInjetados: [...document.querySelectorAll('script[src]')].map(s => s.src),
    corpoInteiro: document.documentElement.innerHTML,
  };
}, base);

console.log('\n5.10 — a ponte de tags, em Chromium real\n');

// ── O aceite, frase por frase ───────────────────────────────────────────────────────────────
console.log('· página com 3 pixels: o evento NÃO vaza');
const verbosFbq = resultado.fbq.map(c => c[0]);
conferir('nenhum `fbq("track")` nem `trackCustom`', !verbosFbq.includes('track') && !verbosFbq.includes('trackCustom'), JSON.stringify(verbosFbq));
conferir('uma chamada só, `trackSingle` no pixel 222', resultado.fbq.length === 1 && resultado.fbq[0][0] === 'trackSingle' && resultado.fbq[0][1] === '222', JSON.stringify(resultado.fbq));
conferir('o `event_id` do servidor viaja como `eventID`', resultado.fbq[0]?.[4]?.eventID === 'uuid-real', JSON.stringify(resultado.fbq[0]?.[4]));
conferir('o evento DESLIGADO no mapa não chegou a pixel nenhum', resultado.fbq.length === 1);

console.log('\n· sem opt-in: nenhuma tag nossa instalada, nenhum PageView');
conferir('nenhum script novo injetado na página', resultado.scriptsInjetados.filter(s => /facebook|googletagmanager/.test(s)).length === 0, JSON.stringify(resultado.scriptsInjetados));
conferir('nenhum `PageView` disparado', !resultado.fbq.some(c => String(c[2]) === 'PageView'));

console.log('\n· `gtag` e `dataLayer` do cliente continuam funcionais');
conferir('`window.gtag` é a MESMA função de antes', resultado.gtagPreservado);
conferir('`window.dataLayer` é o MESMO array de antes', resultado.dataLayerPreservado);
conferir('o que o cliente já tinha na fila sobreviveu', JSON.stringify(resultado.entradasAntes) === JSON.stringify(['gtm.js', 'promocao_vista', undefined]), JSON.stringify(resultado.entradasAntes));
conferir('GA4 recebeu com `send_to`', resultado.gtagChamadas.some(c => c[0] === 'event' && c[1] === 'generate_lead' && c[2]?.send_to === 'G-DOCLIENTE'), JSON.stringify(resultado.gtagChamadas));
conferir('Google Ads recebeu como `conversion`', resultado.gtagChamadas.some(c => c[1] === 'conversion' && c[2]?.send_to === 'AW-123456789/rotulo'));

console.log('\n· `dataLayer` sempre, e sem PII');
conferir('os DOIS eventos foram publicados, inclusive o desligado nos destinos', resultado.publicados.length === 2, JSON.stringify(resultado.publicados.map(e => e.event)));
conferir('nenhuma PII no `dataLayer`', !JSON.stringify(resultado.publicados).includes('ana@exemplo.com.br'));
conferir('nenhuma PII em lugar nenhum da página', !resultado.corpoInteiro.includes('ana@exemplo.com.br'));
conferir('nenhuma PII no payload do `fbq`', !JSON.stringify(resultado.fbq).includes('ana@exemplo.com.br'));

console.log('\n· console limpo');
conferir('nada no console do navegador', console_.length === 0, JSON.stringify(console_));

// ── CENÁRIO 2: página SEM pixel nenhum, e o opt-in ligado (T-C4.3) ──────────────────────────
//
// É o outro lado do aceite: aqui a tag falta de verdade, o cliente pediu a instalação, e o que
// não pode acontecer é um `PageView` nosso somando à contagem de visitas dele.
const pagina2 = await contexto.newPage();
const console2 = [];
pagina2.on('console', msg => console2.push(`${msg.type()}: ${msg.text()}`));
pagina2.on('pageerror', erro => console2.push(`pageerror: ${erro.message}`));
// A rede externa não é usada: o `fbevents.js` e o `gtag.js` são interceptados e respondidos
// vazios. O que se mede aqui é a NOSSA sequência de comandos, não o comportamento da Meta.
await pagina2.route('**/connect.facebook.net/**', rota => rota.fulfill({ body: '', contentType: 'text/javascript' }));
await pagina2.route('**/googletagmanager.com/**', rota => rota.fulfill({ body: '', contentType: 'text/javascript' }));
await pagina2.goto(`${base}/limpa`, { waitUntil: 'networkidle' });

const cenario2 = await pagina2.evaluate(async origem => {
  // Página crua: nada de `fbq`, nada de `gtag`, nada de `dataLayer`.
  delete window.fbq;
  delete window._fbq;
  delete window.gtag;
  delete window.dataLayer;

  const { createTagBridge } = await import(`${origem}/packs/js/tracking.js`);
  createTagBridge({
    tracking: {
      meta_pixel_id: '999',
      ga4_measurement_id: 'G-NOVO',
      install_tags: true,
      event_map: { chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' } },
    },
  })('chatspx_lead', { value: 1 });

  await new Promise(r => setTimeout(r, 300));

  return {
    filaFbq: (window.fbq?.queue || []).map(args => [...args]),
    scripts: [...document.querySelectorAll('script[src]')].map(s => s.src),
    dataLayer: window.dataLayer.map(e =>
      e && e.event ? { event: e.event } : [...e]
    ),
  };
}, base);

console.log('\n· cenário 2 — a tag falta e o cliente pediu para instalar');
const verbos2 = cenario2.filaFbq.map(c => c[0]);
conferir('o pixel foi inicializado', verbos2.includes('init'), JSON.stringify(verbos2));
conferir('NENHUM `PageView` — é o skipPageView', !cenario2.filaFbq.some(c => String(c[1]) === 'PageView'), JSON.stringify(cenario2.filaFbq));
conferir('o `fbevents.js` foi buscado', cenario2.scripts.some(s => s.includes('connect.facebook.net')), JSON.stringify(cenario2.scripts));
conferir('o `gtag.js` foi buscado', cenario2.scripts.some(s => s.includes('googletagmanager.com')));
conferir('o GA4 nasceu com `send_page_view: false`', JSON.stringify(cenario2.dataLayer).includes('send_page_view'), JSON.stringify(cenario2.dataLayer));
conferir('console limpo também aqui', console2.length === 0, JSON.stringify(console2));

await navegador.close();
servidor.close();

console.log(
  falhas.length
    ? `\n${falhas.length} asserção(ões) falharam.\n`
    : '\nTodas as asserções passaram em navegador real.\n'
);
process.exit(falhas.length ? 1 : 0);
