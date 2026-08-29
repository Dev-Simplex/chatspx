/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * O SEXTO ACEITE DO BLOCO 4.20, COM IFRAME DE VERDADE.
 *
 *   "`Esc` fecha o painel aberto por auto-open e devolve o foco ao lançador (2.11)"
 *
 * Os outros cinco aceites do 4.20 são afirmações sobre UM documento (o host) e
 * estão verdes em vitest. Este é sobre DOIS, e sobre duas ORIGENS: o painel roda
 * num iframe cross-origin, o `Esc` chega ao documento de DENTRO dele, e quem
 * fecha o painel e devolve o foco ao lançador é o documento de FORA. Entre os
 * dois há um `postMessage` com `targetOrigin` real e duas validações de origem
 * (`isTrustedFrameOrigin` no host, `isTrustedOrigin` no painel).
 *
 * POR QUE JSDOM NÃO SERVIA — e a prova anterior estava em jsdom. Ela mockava
 * `widget/helpers/utils` (o transporte inteiro) e, no lugar de deixar a mensagem
 * atravessar, chamava `IFrameHelper.events.closeWindow()` À MÃO. Com um
 * `document` só, "o foco entrou no iframe" não é sequer enunciável, e o `Esc`
 * era um `KeyboardEvent` sintético despachado no documento onde o ouvinte já
 * estava — nunca uma tecla roteada pelo navegador até o frame focado. Todo o
 * caminho que pode quebrar em produção era justamente o que ficava de fora.
 *
 * AS TRÊS PERGUNTAS QUE SÓ O NAVEGADOR RESPONDE, e são as três medidas aqui:
 *
 *   1. O auto-open acontece sem NENHUM gesto do visitante. Um iframe de outra
 *      origem consegue puxar o foco para dentro de si sem ativação do usuário?
 *      Se não conseguir, o `Esc` do visitante nunca chega ao painel e o aceite é
 *      falso — sem erro no console, sem teste vermelho em lugar nenhum.
 *   2. Com o foco lá dentro, o `Escape` do TECLADO (não um evento sintético) é
 *      roteado para o documento do iframe, onde mora o ouvinte do 2.11?
 *   3. A mensagem `closeWindow` atravessa a fronteira de origem, o host fecha e
 *      `document.activeElement` do HOST volta a ser o lançador?
 *
 * O QUE É REAL AQUI. O host é `entrypoints/sdk.js` empacotado com Vite —
 * `chatwootSDK.run()`, `createFrame`, `initPostMessageCommunication`, o
 * lançador, o `SDK_CSS` e o auto-open do 4.20 pelo caminho de produção
 * (`onLoad` → `montarTeaserSeConfigurado` → gatilho composto → `podeAbrirSozinho`
 * → `toggleBubble('open')`). O painel é `fixtures/widgetFrame.js`, que importa o
 * bridge real, os handlers reais, o módulo `appConfig` real da store e o
 * `loadedEventConfig` real — ver o cabeçalho de lá para o que é redução.
 *
 * VERMELHO ANTES DE VERDE, DUAS PONTAS, UMA DE CADA VEZ. Asserção negativa passa
 * de graça quando o sujeito nunca existiu, então as duas condições ruins são
 * FORÇADAS e têm de falhar:
 *
 *   · cenário SEM O 2.11 — o painel instala `registerBridgeListeners` (o outro
 *     export do MESMO módulo real: a ponte sem o `Esc`, que é o mundo anterior
 *     ao 2.11). Mesma sequência, e o painel tem de continuar ABERTO. É o que
 *     prova que o verde acima mede o ouvinte, e não o navegador.
 *   · cenário FOCO NO HOST — depois do auto-open, o foco volta para um campo do
 *     site do cliente. O `Esc` tem de não fechar nada. É o que prova que a tecla
 *     está sendo roteada pelo foco de verdade, e não capturada por um ouvinte
 *     global qualquer.
 *
 * DUAS ORIGENS DE MENTIRA, SEM SERVIDOR. `page.route` serve `http://site.test/`
 * (o site do cliente) e `http://painel.test/widget` (o painel). São origens
 * diferentes, como em produção — e é o `document.referrer` do iframe que faz
 * `getParentTargetOrigin()` devolver `http://site.test` em vez de `'*'`. Não usa
 * o harness de porta fixa: `chromium.launch()` direto, sem servidor e sem
 * disputar porta com ninguém.
 *
 *   node app/javascript/sdk/specs/browser/auto-open-escape.check.mjs
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { build } from 'vite';

const RAIZ = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../../..'
);

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// Os mesmos apelidos de `vite.shared.ts`. Escritos aqui porque este arquivo
// constrói com `configFile: false` — um build com a config do projeto arrastaria
// o vite_ruby, o manifest e o diretório `public/vite`, e este verificador não
// escreve um byte em disco (`write: false`).
const alias = {
  vue: path.join(RAIZ, 'node_modules/vue/dist/vue.esm-bundler.js'),
  shared: path.join(RAIZ, 'app/javascript/shared'),
  widget: path.join(RAIZ, 'app/javascript/widget'),
  dashboard: path.join(RAIZ, 'app/javascript/dashboard'),
  helpers: path.join(RAIZ, 'app/javascript/shared/helpers'),
};

const empacotar = async (entrada, nome) => {
  const saida = await build({
    root: RAIZ,
    logLevel: 'error',
    configFile: false,
    resolve: { alias },
    define: { 'process.env.NODE_ENV': '"production"' },
    build: {
      write: false,
      target: 'es2020',
      lib: { entry: entrada, formats: ['iife'], name: nome, fileName: 'b' },
    },
  });
  return saida[0].output[0].code;
};

const HOST_BUNDLE = await empacotar(
  path.join(RAIZ, 'app/javascript/entrypoints/sdk.js'),
  'wootHost'
);
const FRAME_BUNDLE = await empacotar(
  path.join(RAIZ, 'app/javascript/sdk/specs/browser/fixtures/widgetFrame.js'),
  'wootFrame'
);

// O `SDK_CSS` de verdade. Sem ele `woot--hide` não esconde nada, e um `.focus()`
// num elemento `display:none` é no-op — o verificador leria verde por não ter
// estilo, que é o modo mais bobo de medir o próprio ambiente.
const SDK_CSS = readFileSync(
  path.join(RAIZ, 'app/javascript/sdk/sdk.js'),
  'utf8'
).match(/export const SDK_CSS = `([\s\S]*?)\n`;/)[1];

const ORIGEM_SITE = 'http://site.test';
const ORIGEM_PAINEL = 'http://painel.test';
const TOKEN = 'tok-4-20';

const paginaDoSite = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>site do cliente</title>
<style>${SDK_CSS}</style></head>
<body style="margin:0;height:3000px">
  <h2>página do cliente</h2>
  <input id="campo-do-site" />
  <script>window.chatwootSettings = { position: 'right', locale: 'pt_BR' };</script>
  <script>${HOST_BUNDLE}</script>
  <script>
    window.chatwootSDK.run({
      websiteToken: '${TOKEN}',
      baseUrl: '${ORIGEM_PAINEL}',
    });
  </script>
</body></html>`;

// `widgetTriggers` viaja DENTRO do `chatwootWebChannel` do painel: é ele que o
// host recebe no `loaded` e repassa a `montarTeaserSeConfigurado`. Ligar o
// auto-open aqui e não no host é o caminho de produção, não um atalho.
const paginaDoPainel = escLigado => `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>painel</title></head>
<body style="margin:0;background:#fff">
  <h1 tabindex="-1">Conversas</h1>
  <script>
    window.authToken = 'auth-4-20';
    window.chatwootWebChannel = {
      websiteToken: '${TOKEN}',
      widgetColor: '#1f93ff',
      welcomeTitle: '',
      welcomeTagline: '',
      enabledFeatures: [],
      widgetTriggers: { enabled: true, approach: 'aggressive' },
    };
    ${escLigado ? '' : 'window.wootEscLigado = false;'}
  </script>
  <script>${FRAME_BUNDLE}</script>
</body></html>`;

const navegador = await chromium.launch();

/**
 * Sobe o site + o painel, deixa o auto-open acontecer e devolve o estado medido.
 *
 * `antesDoEsc` roda com o painel já aberto: é por onde o cenário "foco no host"
 * tira o foco de dentro do iframe.
 */
const rodar = async ({ escLigado = true, antesDoEsc } = {}) => {
  const ctx = await navegador.newContext({
    viewport: { width: 1280, height: 800 },
  });
  const page = await ctx.newPage();
  const erros = [];
  page.on('pageerror', e => erros.push(String(e)));

  await page.clock.install();
  await page.route('**/*', rota => {
    const url = rota.request().url();
    const painel = url.startsWith(`${ORIGEM_PAINEL}/widget`);
    return rota.fulfill({
      contentType: 'text/html; charset=utf-8',
      body: painel ? paginaDoPainel(escLigado) : paginaDoSite,
    });
  });
  await page.goto(`${ORIGEM_SITE}/`);

  // O lançador só nasce no `onLoad`, que só roda quando o `loaded` do painel
  // atravessa a ponte. Esperar por ele é esperar a ponte inteira funcionar.
  await page
    .locator('.woot-widget-bubble:not(.woot--close)')
    .waitFor({ timeout: 15000 });

  // O gatilho composto do 4.06, que o `aggressive` reaproveita: 30 % de rolagem
  // E 8 s. Nenhum clique, nenhuma tecla — auto-open é isso.
  await page.evaluate(() => {
    window.scrollTo(0, 1500);
    window.dispatchEvent(new Event('scroll'));
  });
  await page.clock.fastForward(9000);

  const abriu = await page
    .waitForFunction(() => window.$chatwoot?.isOpen === true, null, {
      timeout: 5000,
    })
    .then(
      () => true,
      () => false
    );

  // O foco entra por dentro do iframe (`h1.focus()` no documento do painel). Do
  // lado do host isso aparece como `activeElement` sendo o próprio <iframe>.
  const focoNoIframe = await page
    .waitForFunction(
      () => document.activeElement?.id === 'chatwoot_live_chat_widget',
      null,
      { timeout: 5000 }
    )
    .then(
      () => true,
      () => false
    );

  if (antesDoEsc) await antesDoEsc(page);

  await page.keyboard.press('Escape');

  // `fechou` é uma TRANSIÇÃO, nunca o estado final. Medido como
  // `isOpen === false`, ele passaria de graça no caso em que o painel nunca
  // abriu — foi o que aconteceu ao sabotar o `aggressive` de `teaser.js`: o
  // aceite 6 leu verde num navegador onde não havia painel para fechar. Sem
  // abertura não há fechamento, e o verificador diz isso em vez de mentir.
  const fechou = !abriu
    ? 'nao-abriu'
    : await page
        .waitForFunction(() => window.$chatwoot?.isOpen === false, null, {
          timeout: 3000,
        })
        .then(
          () => 'true',
          () => 'false'
        );

  const estado = await page.evaluate(() => {
    const ativo = document.activeElement;
    const lancador = document.querySelector(
      '.woot-widget-bubble:not(.woot--close)'
    );
    return {
      aberto: window.$chatwoot?.isOpen === true,
      focoNoLancador: ativo === lancador,
      idDoAtivo: ativo?.id || ativo?.className || ativo?.tagName || '',
      escondido: document
        .getElementById('cw-widget-holder')
        ?.className.includes('woot--hide'),
      lancadorVisivel:
        lancador && getComputedStyle(lancador).display !== 'none',
    };
  });

  await ctx.close();
  return {
    abriu,
    focoNoIframe,
    fechou,
    erros,
    ...estado,
    // Mesma razão do `fechou`: "está escondido" é o estado de repouso do painel
    // que nunca abriu.
    painelEscondido: abriu ? String(estado.escondido) : 'nao-abriu',
  };
};

// ── VERDE: o caminho de produção, ponta a ponta ─────────────────────────────
const real = await rodar();

check(
  'sem erro de página em nenhum dos dois documentos',
  String(real.erros.length),
  '0'
);
check(
  'o painel abre SOZINHO — nenhum clique, nenhuma tecla (4.20)',
  String(real.abriu),
  'true'
);
// O que esta asserção mede NÃO é "o Vue focou" — é que o navegador PERMITE a um
// iframe de outra origem puxar o foco para dentro de si com zero ativação do
// usuário. Se Chromium recusasse, o `Esc` do visitante ficaria no documento do
// site e o aceite 6 seria falso em produção, sem erro em lugar nenhum. Quem
// chama o `focus()` aqui é o `watch` sobre o getter real, em
// `fixtures/widgetFrame.js` — ver o cabeçalho de lá.
check(
  'e o foco ENTRA no iframe de outra origem, sem gesto do visitante',
  String(real.focoNoIframe),
  'true'
);
check(
  'aceite 6 — o Esc do teclado fecha o painel aberto por auto-open',
  real.fechou,
  'true'
);
check('e o painel fica de fato escondido', real.painelEscondido, 'true');
check(
  'e o foco volta ao LANÇADOR, no documento do host (2.11)',
  String(real.focoNoLancador),
  'true'
);
// O `.focus()` de um elemento `display:none` é no-op e devolveria `<body>`. Esta
// asserção é o que separa "voltou ao lançador" de "não foi para lugar nenhum".
check(
  'e o lançador estava visível quando recebeu o foco (focus em display:none é no-op)',
  String(real.lancadorVisivel),
  'true'
);

// ── VERMELHO 1: a mesma sequência SEM o ouvinte do 2.11 ─────────────────────
const semEsc = await rodar({ escLigado: false });
check(
  'controle — sem o Esc do 2.11 o painel abre igual (a diferença é só o ouvinte)',
  String(semEsc.abriu && semEsc.focoNoIframe),
  'true'
);
check(
  'VERMELHO FORÇADO — sem o ouvinte do 2.11, o Esc NÃO fecha o painel',
  String(semEsc.aberto),
  'true'
);
check(
  'e sem fechar não há foco no lançador para devolver',
  String(semEsc.focoNoLancador),
  'false'
);

// ── VERMELHO 2: o foco fora do iframe ──────────────────────────────────────
//
// Isto também DOCUMENTA um limite medido, e ele é do desenho do 2.11, não um
// defeito que este bloco conserte: o ouvinte do `Esc` mora no documento do
// PAINEL. O visitante que clica de volta na página do cliente e só então aperta
// `Esc` não fecha o painel — a tecla nunca chega ao frame. Fechá-la dali exigiria
// um segundo ouvinte no host, que custa bytes do `sdk.js` a 100% dos visitantes
// de todos os sites (teto A13) por um nível que nasce desligado, e mudaria o
// comportamento de TODO cliente, não só de quem ligou o `aggressive`. Fica
// registrado como medição, não como conserto.
const focoNoHost = await rodar({
  antesDoEsc: async page => {
    await page.locator('#campo-do-site').focus();
  },
});
check(
  'controle — o painel tinha aberto e o foco tinha entrado no iframe',
  String(focoNoHost.abriu && focoNoHost.focoNoIframe),
  'true'
);
check(
  'VERMELHO FORÇADO — com o foco de volta no site, o Esc não chega ao painel',
  String(focoNoHost.aberto),
  'true'
);
check(
  'e o foco continua onde o visitante o deixou, no campo do site',
  focoNoHost.idDoAtivo,
  'campo-do-site'
);

await navegador.close();
const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
