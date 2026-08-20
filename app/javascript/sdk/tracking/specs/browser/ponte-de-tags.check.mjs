/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * Bloco 5.10 — o aceite da ponte de tags MEDIDO EM NAVEGADOR, não em jsdom.
 *
 * ── POR QUE ELE EXISTE AO LADO DE `specs/tags.spec.js` ──────────────────────────────────
 *
 * O spec de unidade prova que a função chama a função. Ele monta um `window.fbq` que é um
 * `vi.fn()`, um `dataLayer` que é um array literal, e verifica a chamada. Isso é necessário
 * e não é suficiente: o aceite do bloco é *"página com 3 pixels: o evento **não vaza**"*, e
 * "não vazar" é comportamento de um `window` de verdade — com `document`, com ordem de
 * execução de script, com um `dataLayer` que outra tag já mexeu e com o console que o
 * próprio navegador escreve.
 *
 * Nesta execução o jsdom já deu verde três vezes em telas que o Chromium reprovou.
 *
 * O que este arquivo mede que o de unidade não pode medir:
 *   · o artefato **CONSTRUÍDO** (`public/packs/js/tracking.js`), minificado, importado como
 *     módulo ES real — não o fonte resolvido pelo bundler de teste;
 *   · `window.gtag` e `window.dataLayer` do cliente **sobrevivendo por identidade**
 *     (`===`), que é a regra RC2 e que um mock não consegue perder;
 *   · o **console do Chromium**, com os avisos que ele emite por conta própria — "console
 *     limpo" é aceite deste bloco e não existe em jsdom.
 *
 * ── COMO RODAR ──────────────────────────────────────────────────────────────────────────
 *
 *   npx vite build --config vite.tracking.config.ts
 *   node app/javascript/sdk/tracking/specs/browser/ponte-de-tags.check.mjs
 *
 * ⚠️ NÃO USA O HARNESS DE PORTA FIXA. `chromium.launch()` direto e um servidor em porta
 * EFÊMERA (`listen(0)`) — as portas 3038/3999/8899 estão sob tranca do coordenador. O
 * servidor existe porque `import()` de módulo ES precisa de uma origem http; `file://` não
 * serve.
 *
 * Sai 0 quando tudo passa, 1 quando alguma asserção falha, 2 quando não conseguiu medir —
 * "não consegui medir" nunca pode sair como verde.
 */
import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { chromium } from 'playwright';

const ARTEFATO = path.join(process.cwd(), 'public/packs/js/tracking.js');

if (!existsSync(ARTEFATO)) {
  console.error(
    `[5.10] artefato ausente: ${ARTEFATO}\n` +
      'Rode `npx vite build --config vite.tracking.config.ts` antes.'
  );
  process.exit(2);
}

const results = [];
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}` +
      (ok
        ? ''
        : `\n        esperado=${JSON.stringify(expected)}  recebido=${JSON.stringify(actual)}`)
  );
};

/**
 * A página do cliente como ela é: GTM já carregado, `dataLayer` com coisas dentro, um `gtag`
 * próprio, e TRÊS pixels da Meta — o dele, o da agência, o do marketplace. É exatamente a
 * página em que `fbq('track', …)` conta a conversão nas três contas.
 *
 * Os dublês são LOCAIS: nenhuma chamada sai para `connect.facebook.net` nem para o Google. O
 * que se mede aqui é a NOSSA sequência de comandos, não o comportamento da Meta.
 */
const PAGINA_COM_PIXELS = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>site do cliente</title>
<script>
  window.dataLayer = [{ event: 'gtm.js' }, { event: 'promocao_vista' }];
  window.gtagDoCliente = function () { window.gtagChamadas.push([].slice.call(arguments)); };
  window.gtagChamadas = [];
  window.gtag = window.gtagDoCliente;
  window.dataLayer.push(['config', 'G-DOCLIENTE']);

  window.fbqChamadas = [];
  window.fbq = function () { window.fbqChamadas.push([].slice.call(arguments)); };
  window.fbq.getState = function () {
    return { pixels: [{ id: '111' }, { id: '222' }, { id: '333' }] };
  };
</script>
</head><body><h1>site do cliente</h1></body></html>`;

/** A outra página: nenhuma tag, nenhum `dataLayer`. É o cliente que só usa GTM — ou nada. */
const PAGINA_CRUA = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>site cru</title></head>
<body><h1>site cru</h1></body></html>`;

const servidor = http.createServer((req, res) => {
  if (req.url.startsWith('/packs/js/tracking.js')) {
    res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    res.end(readFileSync(ARTEFATO));
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(req.url.startsWith('/cru') ? PAGINA_CRUA : PAGINA_COM_PIXELS);
});

await new Promise(resolve => {
  servidor.listen(0, '127.0.0.1', resolve);
});
const base = `http://127.0.0.1:${servidor.address().port}`;
const browser = await chromium.launch();
const contexto = await browser.newContext();

const abrir = async caminho => {
  const pagina = await contexto.newPage();
  const mensagens = [];
  pagina.on('console', m => mensagens.push(`${m.type()}: ${m.text()}`));
  pagina.on('pageerror', e => mensagens.push(`pageerror: ${e.message}`));
  // Nenhuma requisição externa deve acontecer; se alguma tentar, ela é registrada e reprovada.
  const externas = [];
  await pagina.route('**/*', rota => {
    const url = rota.request().url();
    if (!url.startsWith(base)) {
      externas.push(url);
      return rota.abort();
    }
    return rota.continue();
  });
  await pagina.goto(`${base}${caminho}`, { waitUntil: 'networkidle' });
  return { pagina, mensagens, externas };
};

const MAPA = {
  chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
  chatspx_conversation_started: {
    enabled: true,
    meta: 'Contact',
    ga4: 'conversation_start',
  },
  chatspx_widget_opened: {
    enabled: false,
    meta: 'ViewContent',
    ga4: 'widget_open',
  },
};

console.log('\n5.10 — a ponte de tags, em Chromium real\n');

// ═══ CENÁRIO 1 — a página com três pixels ═══════════════════════════════════════════════
const c1 = await abrir('/');
const r1 = await c1.pagina.evaluate(
  async ({ origem, mapa }) => {
    const { createTagsBridge } = await import(`${origem}/packs/js/tracking.js`);

    const gtagAntes = window.gtag;
    const dataLayerAntes = window.dataLayer;
    const filaAntes = window.dataLayer.length;

    const ponte = createTagsBridge({
      tracking: {
        meta_pixel_id: '222',
        ga4_measurement_id: 'G-DOCLIENTE',
        google_ads_send_to: 'AW-123456789/rotulo',
        event_map: mapa,
      },
      isAllowed: () => true,
    });

    // 1. evento com valor — deve ir aos quatro destinos
    ponte.onTrackingEvent({
      name: 'chatspx_lead',
      properties: {
        value: 99,
        currency: 'BRL',
        email: 'ana@exemplo.com.br',
        contato: { phone_number: '+5565999', cidade: 'Cuiabá' },
      },
      eventId: 'uuid-real',
    });
    // 2. evento DESLIGADO no mapa — só `dataLayer`
    ponte.onTrackingEvent({
      name: 'chatspx_widget_opened',
      properties: { inbox_id: 7 },
    });
    // 3. evento FORA do mapa — só `dataLayer` (T-C4.10, o padrão de fábrica)
    ponte.onTrackingEvent({
      name: 'chatspx_orcamento_pedido',
      properties: { plano: 'pro' },
    });
    // 4. o caminho do 5.04: evento de `window` traduzido pelo contrato
    ponte.onWindowEvent('chatwoot:conversation-created', {
      conversation_id: 42,
    });
    // 5. evento de `window` SEM contrapartida de tracking (`tracking: null` no contrato)
    ponte.onWindowEvent('chatwoot:csat-submitted', { rating: 5 });

    return {
      gtagPreservado: window.gtag === gtagAntes,
      dataLayerPreservado: window.dataLayer === dataLayerAntes,
      filaDoCliente: window.dataLayer
        .slice(0, filaAntes)
        .map(e => (e && e.event) || e[0]),
      publicados: window.dataLayer
        .filter(
          e =>
            e && typeof e.event === 'string' && e.event.startsWith('chatspx_')
        )
        .map(e => JSON.parse(JSON.stringify(e))),
      fbq: window.fbqChamadas,
      gtag: window.gtagChamadas,
      pixelReconhecido: ponte.metaPixelInicializado(),
      ga4Reconhecido: ponte.ga4Configurado(),
      scripts: [...document.querySelectorAll('script[src]')].map(s => s.src),
      documento: document.documentElement.innerHTML,
    };
  },
  { origem: base, mapa: MAPA }
);

console.log('· o aceite: página com 3 pixels, o evento não vaza');
check(
  'nenhum `fbq("track")` nem `trackCustom` — os verbos que disparam em TODOS os pixels',
  r1.fbq.map(c => c[0]).filter(v => v === 'track' || v === 'trackCustom'),
  []
);
// Dois eventos habilitados no mapa disparam na Meta (`chatspx_lead` pelo caminho de 5.16 e
// `chatspx_conversation_started` pela tradução de 5.04). A asserção forte não é a CONTAGEM —
// é que TODA chamada nomeia o pixel do cliente, e nenhuma outra.
check(
  'toda chamada ao `fbq` é `trackSingle` no pixel 222 — nenhuma escapa para os outros dois',
  r1.fbq.map(c => [c[0], c[1]]),
  [
    ['trackSingle', '222'],
    ['trackSingle', '222'],
  ]
);
check(
  'e os eventos são os dois habilitados no mapa, com o nome do DESTINO',
  r1.fbq.map(c => c[2]),
  ['Lead', 'Contact']
);
check(
  'o `event_id` do servidor viaja como `eventID` (é o que a Meta deduplica em 5.13)',
  r1.fbq[0]?.[4],
  { eventID: 'uuid-real' }
);
check(
  'o pixel configurado foi reconhecido na página',
  r1.pixelReconhecido,
  true
);

console.log('\n· `gtag` e `dataLayer` do cliente continuam funcionais (RC2)');
check('`window.gtag` é a MESMA função de antes', r1.gtagPreservado, true);
check(
  '`window.dataLayer` é o MESMO array de antes',
  r1.dataLayerPreservado,
  true
);
check('a fila que o cliente já tinha sobreviveu', r1.filaDoCliente, [
  'gtm.js',
  'promocao_vista',
  'config',
]);
check('o GA4 do cliente foi reconhecido', r1.ga4Reconhecido, true);
check(
  'GA4 recebeu o evento com `send_to` — nunca sem',
  r1.gtag.find(c => c[1] === 'generate_lead')?.[2],
  {
    value: 99,
    currency: 'BRL',
    contato: { cidade: 'Cuiabá' },
    send_to: 'G-DOCLIENTE',
  }
);
check(
  'Google Ads recebeu como `conversion`, com `transaction_id`',
  r1.gtag.find(c => c[1] === 'conversion')?.[2],
  {
    send_to: 'AW-123456789/rotulo',
    value: 99,
    currency: 'BRL',
    transaction_id: 'uuid-real',
  }
);

console.log(
  '\n· `dataLayer` sempre — e é ele que sustenta o "somente dataLayer" (T-C4.10)'
);
check(
  'os quatro fatos foram publicados, inclusive o desligado e o que não está no mapa',
  r1.publicados.map(e => e.event),
  [
    'chatspx_lead',
    'chatspx_widget_opened',
    'chatspx_orcamento_pedido',
    'chatspx_conversation_started',
  ]
);
check(
  'o evento DESLIGADO no mapa não chegou a tag nenhuma',
  [
    r1.fbq.some(c => c[2] === 'ViewContent'),
    r1.gtag.some(c => c[1] === 'widget_open'),
  ],
  [false, false]
);
check(
  'o evento FORA do mapa não chegou a tag nenhuma',
  r1.gtag.some(c => String(c[1]).includes('orcamento')),
  false
);
check(
  '`onWindowEvent` traduziu `chatwoot:conversation-created` pelo contrato',
  r1.publicados.find(e => e.event === 'chatspx_conversation_started')
    ?.conversation_id,
  42
);
check(
  '`tracking: null` no contrato não vira evento de tracking (o CSAT do §6.1)',
  r1.publicados.some(e => String(e.event).includes('csat')),
  false
);

console.log(
  '\n· PII (RC5) — o `window` do cliente é legível por qualquer script de terceiro'
);
check(
  'nenhuma PII no `dataLayer`',
  JSON.stringify(r1.publicados).includes('ana@exemplo'),
  false
);
check(
  'nenhuma PII no payload do `fbq`',
  JSON.stringify(r1.fbq).includes('+5565999'),
  false
);
check(
  'nenhuma PII no payload do `gtag`',
  JSON.stringify(r1.gtag).includes('ana@exemplo'),
  false
);
check(
  'a limpeza é EM PROFUNDIDADE: PII aninhada some e o irmão dela fica',
  r1.publicados[0]?.contato,
  { cidade: 'Cuiabá' }
);
check(
  'nenhuma PII em lugar nenhum do documento',
  r1.documento.includes('ana@exemplo'),
  false
);

console.log('\n· nada instalado, nada pedido para fora, console limpo');
check(
  'nenhum script de terceiro injetado',
  r1.scripts.filter(s => !s.startsWith(base)),
  []
);
check('nenhuma requisição externa tentada', c1.externas, []);
check('console do navegador vazio', c1.mensagens, []);

// ═══ CENÁRIO 2 — a página crua ══════════════════════════════════════════════════════════
//
// Sem `fbq`, sem `gtag`, sem `dataLayer`. É o cliente que integra só por GTM — e é aqui que
// "somente dataLayer" precisa provar que é um modo de verdade, e não uma promessa.
const c2 = await abrir('/cru');
const r2 = await c2.pagina.evaluate(
  async ({ origem, mapa }) => {
    const { createTagsBridge } = await import(`${origem}/packs/js/tracking.js`);

    const ponte = createTagsBridge({
      tracking: {
        meta_pixel_id: '999',
        ga4_measurement_id: 'G-NOVO',
        google_ads_send_to: 'AW-1/x',
        event_map: mapa,
      },
      isAllowed: () => true,
    });
    ponte.onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 10 },
      eventId: 'u2',
    });

    return {
      dataLayer: (window.dataLayer || []).map(e => e && e.event),
      criouFbq: typeof window.fbq !== 'undefined',
      criouGtag: typeof window.gtag !== 'undefined',
      scripts: [...document.querySelectorAll('script[src]')].map(s => s.src),
      reconheceuPixel: ponte.metaPixelInicializado(),
    };
  },
  { origem: base, mapa: MAPA }
);

console.log('\n· cenário 2 — página sem tag nenhuma');
check('o `dataLayer` foi criado e recebeu o evento', r2.dataLayer, [
  'chatspx_lead',
]);
check(
  'NENHUM `fbq` foi criado — nada nosso instalado sem opt-in',
  r2.criouFbq,
  false
);
check('NENHUM `gtag` foi criado', r2.criouGtag, false);
check(
  'nenhum script injetado — e portanto nenhum `PageView` duplicado',
  r2.scripts,
  []
);
check(
  'o pixel configurado NÃO é reconhecido (ele não está na página)',
  r2.reconheceuPixel,
  false
);
check('nenhuma requisição externa tentada', c2.externas, []);
check('console do navegador vazio', c2.mensagens, []);

// ═══ CENÁRIO 3 — consentimento negado (T-C7.3) ══════════════════════════════════════════
const c3 = await abrir('/');
const r3 = await c3.pagina.evaluate(
  async ({ origem, mapa }) => {
    const { createTagsBridge } = await import(`${origem}/packs/js/tracking.js`);
    const config = {
      meta_pixel_id: '222',
      ga4_measurement_id: 'G-DOCLIENTE',
      google_ads_send_to: 'AW-1/x',
      event_map: mapa,
    };

    createTagsBridge({
      tracking: config,
      isAllowed: () => false,
    }).onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 1 },
    });
    const negado = {
      fbq: window.fbqChamadas.length,
      gtag: window.gtagChamadas.length,
    };

    createTagsBridge({
      tracking: config,
      isAllowed: p => p === 'analytics_storage',
    }).onTrackingEvent({ name: 'chatspx_lead', properties: { value: 1 } });

    return {
      negado,
      soAnalytics: {
        fbq: window.fbqChamadas.length,
        gtagEventos: window.gtagChamadas.map(c => c[1]),
      },
      publicados: window.dataLayer.filter(e => e?.event === 'chatspx_lead')
        .length,
    };
  },
  { origem: base, mapa: MAPA }
);

console.log('\n· cenário 3 — o gate de consentimento vem ANTES do disparo');
check('com tudo negado, nenhuma tag disparou', r3.negado, { fbq: 0, gtag: 0 });
check(
  'mas o `dataLayer` recebeu as duas vezes — publicar não é disparar',
  r3.publicados,
  2
);
check('`analytics_storage` concedido não libera a Meta', r3.soAnalytics.fbq, 0);
check(
  'e libera o GA4 sem liberar o Ads (que é `ad_storage`)',
  r3.soAnalytics.gtagEventos,
  ['generate_lead']
);
check('console do navegador vazio', c3.mensagens, []);

await browser.close();
servidor.close();

const falhas = results.filter(r => !r.ok);
console.log(
  falhas.length
    ? `\n${falhas.length} de ${results.length} asserções FALHARAM.\n`
    : `\n${results.length} asserções passaram em navegador real.\n`
);
process.exit(falhas.length ? 1 : 0);
