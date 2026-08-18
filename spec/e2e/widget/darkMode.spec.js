/**
 * Mecanismo de aceite do bloco 2.10, em NAVEGADOR DE VERDADE.
 *
 * ACEITE (§2.2): «Sem `darkMode` configurado e SO escuro, o widget abre escuro;
 * trocar o tema do SO reflete **sem remount**».
 *
 * Por que este arquivo existe além dos testes de unidade: as duas metades do
 * aceite são de CASCATA e de EVENTO DO NAVEGADOR, e nenhuma das duas é
 * observável em jsdom.
 *
 *   · `color-scheme` só tem efeito medível via `getComputedStyle` do
 *     documento real — é ele que manda o Chromium desenhar a barra de rolagem,
 *     o `caret` e os controles nativos em modo escuro. jsdom não implementa
 *     cascata de verdade e diria "ok" para qualquer coisa.
 *
 *   · "sem remount" é o `change` do `MediaQueryList`, que o Playwright dispara
 *     de verdade com `emulateMedia`. Testar isso com um dublê provaria que o
 *     dublê funciona.
 *
 * O cenário `theme=auto` do harness **omite** `darkMode` de
 * `window.chatwootSettings` — é a ausência de configuração, não um terceiro
 * tema. Os 16 snapshots continuam vindo de `light`/`dark` e não são tocados
 * por este arquivo.
 *
 * NÃO usa `127.0.0.1` por preguiça: o harness inteiro é servido por três
 * processos Node locais (portas 3038/3999/8899) e não passa por Rails, então
 * não há `Rack::Attack` nem safelist de localhost no caminho — a cicatriz que
 * proíbe validar por `127.0.0.1` é sobre requisição que atravessa o Rails.
 */
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const ANCORA_HOME = 'Estamos conectados.';

const abrirWidget = async (page, { theme }) => {
  await page.goto(`${HOST_URL}/?scenario=home&theme=${theme}`, {
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

  // Âncora de conteúdo forte, não `networkidle`: espera o texto que só existe
  // quando a home terminou de montar.
  await expect(frame.getByText(ANCORA_HOME, { exact: true })).toBeVisible();

  return frame;
};

// Lê o que o navegador REALMENTE aplicou ao documento do iframe.
//
// A classe fica no `<html>`; o `color-scheme` fica no container do app
// (`.woot-widget-app`) e não no `:root`, por uma razão medida: no `:root` o
// agente de usuário pinta o CANVAS do documento, e o documento do widget é
// transparente de propósito — ver o comentário longo em `_tokens.scss`. O que o
// visitante ganha com `color-scheme` (barra de rolagem, `caret`, controles
// nativos) está todo DENTRO do container, e a propriedade é herdada.
const lerRaizDoWidget = async frame => ({
  colorScheme: await frame
    .locator('.woot-widget-app')
    .evaluate(el => getComputedStyle(el).colorScheme),
  temClasseDark: await frame
    .locator('html')
    .evaluate(raiz => raiz.classList.contains('dark')),
});

// Luminância relativa WCAG do que o motor computou. `color-scheme: dark` e a
// classe `dark` são SINAIS de tema; a cor que saiu é o EFEITO. Medir só os
// sinais deixaria passar um `!important` de terceiro que prendesse a superfície
// numa cor — a forma exata de defeito que já mordeu esta base três vezes, e que
// passa verde em jsdom porque jsdom não resolve cascata.
//
// ⚠️ MEDE A SUPERFÍCIE QUE PINTA, NÃO `#app`. A primeira versão apontava para
// `#app` e subia pelos ancestrais atrás de um fundo opaco. Só que o documento
// do widget é transparente de propósito (o iframe flutua sobre o site do
// cliente), então o laço chegava ao topo sem achar nada e devolvia
// `rgba(0, 0, 0, 0)` → luminância 0. No tema CLARO isso reprovou; no ESCURO
// PASSOU — pelo motivo errado, porque 0 < 0,1. Um falso verde perfeito: a
// asserção certa, no elemento errado.
//
// Quem pinta o painel é a `div` raiz de `App.vue` (`bg-n-slate-2
// dark:bg-n-solid-1`). É ela que o visitante vê, e é ela que se mede.
const SUPERFICIE_DO_PAINEL = '#app > div';

const luminanciaComputada = (frame, seletor = SUPERFICIE_DO_PAINEL) =>
  frame
    .locator(seletor)
    .first()
    .evaluate(elemento => {
      const fundo = getComputedStyle(elemento).backgroundColor;
      const canais = fundo.match(/[\d.]+/g).map(Number);
      const alfa = canais.length > 3 ? canais[3] : 1;
      const linear = canais.slice(0, 3).map(canal => {
        const n = canal / 255;
        return n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4;
      });
      return {
        cor: fundo,
        alfa,
        luminancia:
          0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2],
      };
    });

// Guarda contra o falso verde acima: uma superfície transparente não tem cor
// para medir, e `luminancia === 0` ali significa "não medi nada", não "escuro".
const exigirSuperficieOpaca = medida => {
  expect(
    medida.alfa,
    `superfície transparente (${medida.cor}) — não há cor computada para medir`
  ).toBeGreaterThan(0.99);
};

test.describe('2.10 — dark mode no documento do widget', () => {
  test('sem `darkMode` configurado e SO ESCURO, o widget abre escuro', async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: 'dark' });
    const frame = await abrirWidget(page, { theme: 'auto' });

    const raiz = await lerRaizDoWidget(frame);
    expect(raiz.temClasseDark).toBe(true);
    expect(raiz.colorScheme).toBe('dark');

    // E a superfície REALMENTE ficou escura. `color-scheme` é o sinal; esta é
    // a cor que o visitante enxerga.
    const medida = await luminanciaComputada(frame);
    exigirSuperficieOpaca(medida);
    expect(medida.luminancia).toBeLessThan(0.1);
  });

  test('sem `darkMode` configurado e SO CLARO, o widget abre claro', async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: 'light' });
    const frame = await abrirWidget(page, { theme: 'auto' });

    const raiz = await lerRaizDoWidget(frame);
    expect(raiz.temClasseDark).toBe(false);
    expect(raiz.colorScheme).toBe('light');

    const medida = await luminanciaComputada(frame);
    exigirSuperficieOpaca(medida);
    expect(medida.luminancia).toBeGreaterThan(0.5);
  });

  test('trocar o tema do SO reflete SEM REMOUNT', async ({ page }) => {
    await page.emulateMedia({ colorScheme: 'light' });
    const frame = await abrirWidget(page, { theme: 'auto' });
    expect(await lerRaizDoWidget(frame)).toEqual({
      colorScheme: 'light',
      temClasseDark: false,
    });

    // Marca a instância viva do app. Se algo remontar o widget, a marca some —
    // é assim que "sem remount" deixa de ser afirmação e vira medição.
    await frame.locator('body').evaluate(() => {
      window.marcaDeInstanciaE2E = 'antes-da-troca';
    });

    await page.emulateMedia({ colorScheme: 'dark' });

    await expect
      .poll(() => lerRaizDoWidget(frame).then(r => r.temClasseDark), {
        timeout: 5000,
      })
      .toBe(true);

    const depois = await lerRaizDoWidget(frame);
    expect(depois.colorScheme).toBe('dark');

    const marca = await frame
      .locator('body')
      .evaluate(() => window.marcaDeInstanciaE2E);
    expect(marca).toBe('antes-da-troca');

    // A cor acompanhou de verdade, não só a classe.
    const depoisDaTroca = await luminanciaComputada(frame);
    exigirSuperficieOpaca(depoisDaTroca);
    expect(depoisDaTroca.luminancia).toBeLessThan(0.1);

    // E volta, na mesma instância.
    await page.emulateMedia({ colorScheme: 'light' });
    await expect
      .poll(() => lerRaizDoWidget(frame).then(r => r.colorScheme), {
        timeout: 5000,
      })
      .toBe('light');
  });

  test('escolha explícita do cliente vence a preferência do SO', async ({
    page,
  }) => {
    // Regressão que a mudança de default poderia causar: quem escreveu
    // `darkMode: 'light'` no snippet não pode passar a ver o widget escuro só
    // porque o sistema do visitante está escuro.
    await page.emulateMedia({ colorScheme: 'dark' });
    const frame = await abrirWidget(page, { theme: 'light' });

    const raiz = await lerRaizDoWidget(frame);
    expect(raiz.temClasseDark).toBe(false);
    expect(raiz.colorScheme).toBe('light');
  });

  test('a área da conversa não contradiz o documento', async ({ page }) => {
    // O defeito concreto: painel escuro com `color-scheme: light` na `div` das
    // mensagens, ou seja, barra de rolagem clara dentro do chat escuro.
    await page.emulateMedia({ colorScheme: 'dark' });
    const frame = await abrirWidget(page, { theme: 'auto' });

    await frame.locator('body').evaluate(async () => {
      await window.WOOT_WIDGET.$router.replace({ name: 'messages' });
    });

    const container = frame.locator('.conversation--container');
    await expect(container).toBeAttached();

    const esquemaDaConversa = await container.evaluate(
      elemento => getComputedStyle(elemento).colorScheme
    );
    expect(esquemaDaConversa).toBe('dark');
  });
});
