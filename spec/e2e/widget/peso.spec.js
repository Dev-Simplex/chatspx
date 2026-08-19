// Mecanismo de aceite do bloco 2.18 — o peso do widget, medido no NAVEGADOR.
//
// O teto em bytes vive em `scripts/widget-size.mjs`, que mede o artefato de
// producao. Este arquivo mede a outra metade do aceite, e ela nao sai do
// artefato: as duas bibliotecas tem de DEIXAR DE EXISTIR no `window` do iframe.
//
// Por que as duas metades: um chunk de vendor separado encolhe o bundle de
// entrada e passa no teto de bytes enquanto o navegador continua BAIXANDO E
// EXECUTANDO a biblioteca — o `window` e o unico lugar onde essa diferenca
// aparece. E o inverso tambem: `window.__SENTRY__` undefined nao prova que o
// codigo nao veio junto, so que nao rodou. Por isso o spec confere as duas
// coisas: o objeto global E a lista de recursos que a pagina buscou.
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';

const abrirWidget = async (page, cenario = 'home') => {
  await page.goto(`${HOST_URL}/?scenario=${cenario}&theme=light`, {
    waitUntil: 'domcontentloaded',
  });
  await expect
    .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
      timeout: 30000,
    })
    .toBe(true);
  const frame = page.frameLocator('#chatwoot_live_chat_widget');
  await expect(frame.locator('#app')).toBeVisible();
  await page.evaluate(() => window.$chatwoot.toggle('open'));
  await expect
    .poll(
      () =>
        frame
          .locator('body')
          .evaluate(() =>
            Boolean(window.WOOT_WIDGET?.$router && window.WOOT_WIDGET?.$store)
          ),
      { timeout: 30000 }
    )
    .toBe(true);
  return frame;
};

/** Nomes dos recursos que o DOCUMENTO DO WIDGET (nao o host) buscou. */
const recursosDoWidget = frame =>
  frame
    .locator('body')
    .evaluate(() =>
      performance.getEntriesByType('resource').map(entrada => entrada.name)
    );

const globaisNoIframe = frame =>
  frame.locator('body').evaluate(() => ({
    // `__SENTRY__` e o nome que o proprio SDK crava no `window`; e ele que o
    // aceite mede, entao o sublinhado nao e escolha nossa.
    // eslint-disable-next-line no-underscore-dangle
    sentry: typeof window.__SENTRY__,
    amplitude: typeof window.amplitude,
  }));

test('2.18 — Sentry e Amplitude nao existem no window do iframe', async ({
  page,
}) => {
  const frame = await abrirWidget(page);
  expect(await globaisNoIframe(frame)).toEqual({
    sentry: 'undefined',
    amplitude: 'undefined',
  });
});

test('2.18 — o widget nao BUSCA Sentry nem Amplitude em nenhuma das telas', async ({
  page,
}) => {
  const frame = await abrirWidget(page, 'messages');
  await frame.locator('body').evaluate(async () => {
    await window.WOOT_WIDGET.$router.replace({ name: 'messages' });
  });
  const recursos = await recursosDoWidget(frame);
  const proibidos = recursos.filter(nome =>
    /@sentry|sentry[-.]|@amplitude|amplitude[-.]/i.test(nome)
  );
  expect(
    proibidos,
    `recursos proibidos buscados: ${proibidos.join(', ')}`
  ).toEqual([]);
});

/**
 * O FormKit e medido pelo que ele DEIXA NA APP, e nao pelo nome do arquivo que
 * a rede buscou. A primeira versao deste exemplo filtrava `performance` por
 * /formkit/ e reprovava com o pre-chat funcionando na tela: no dev do harness o
 * Vite serve a dependencia pre-empacotada como `deps/chunk-OL46QLBJ.js`, um
 * nome que nao contem "formkit". O nome do chunk e detalhe do empacotador; o
 * que o aceite quer saber e se o plugin foi instalado antes ou depois.
 *
 * `provides` do appContext e onde o plugin poe `FormKitOptions` e
 * `FormKitConfig` — foi verificado na propria pagina, e e por simbolo, entao
 * `Object.keys` nao os enxerga.
 */
const simbolosDaApp = frame =>
  frame
    .locator('body')
    .evaluate(() =>
      Object.getOwnPropertySymbols(
        window.WOOT_WIDGET.$.appContext.provides
      ).map(simbolo => simbolo.description ?? String(simbolo))
    );

test('2.18 — o FormKit so entra na app quando a rota do pre-chat abre', async ({
  page,
}) => {
  const frame = await abrirWidget(page);
  const doFormKit = lista => lista.filter(nome => /formkit/i.test(nome));

  const antes = doFormKit(await simbolosDaApp(frame));
  expect(
    antes,
    `o plugin do FormKit ja estava instalado no boot: ${antes.join(', ')}`
  ).toEqual([]);

  await frame.locator('body').evaluate(async () => {
    await window.WOOT_WIDGET.$router.replace({ name: 'prechat-form' });
  });
  // O formulario e o unico consumidor do FormKit: ve-lo desenhado prova que o
  // plugin chegou a tempo, que e a parte que a troca de eager para lazy poderia
  // quebrar sem que o peso acusasse nada.
  await expect(frame.locator('form')).toBeVisible({ timeout: 30000 });

  expect(doFormKit(await simbolosDaApp(frame)).sort()).toEqual([
    'FormKitConfig',
    'FormKitOptions',
  ]);
});

test('2.18 — o boot busca UM idioma, nao os 41', async ({ page }) => {
  const frame = await abrirWidget(page);
  const locales = (await recursosDoWidget(frame)).filter(nome =>
    /widget\/i18n\/locale\//.test(nome)
  );
  // `en` e estatico (fallback) e por isso nao aparece como recurso proprio no
  // build de producao; no dev do harness ele aparece. O que o aceite proibe e a
  // TABELA INTEIRA vir junto: com os 41 imports estaticos de antes, este numero
  // era 41.
  expect(
    locales.length,
    `locales buscados: ${locales.length} — ${locales.join(', ')}`
  ).toBeLessThanOrEqual(2);
});
