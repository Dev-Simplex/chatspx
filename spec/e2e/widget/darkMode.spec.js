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

// Lê o que o navegador REALMENTE aplicou ao `:root` do documento do iframe.
const lerRaizDoWidget = frame =>
  frame.locator('html').evaluate(raiz => ({
    colorScheme: getComputedStyle(raiz).colorScheme,
    temClasseDark: raiz.classList.contains('dark'),
  }));

// Luminância relativa WCAG do que o motor computou. `color-scheme: dark` e a
// classe `dark` são SINAIS de tema; a cor que saiu é o EFEITO. Medir só os
// sinais deixaria passar um `!important` de terceiro que prendesse a superfície
// numa cor — a forma exata de defeito que já mordeu esta base três vezes, e que
// passa verde em jsdom porque jsdom não resolve cascata.
const luminanciaComputada = (frame, seletor) =>
  frame.locator(seletor).evaluate(elemento => {
    let alvo = elemento;
    let fundo = getComputedStyle(alvo).backgroundColor;
    while (
      alvo.parentElement &&
      (fundo === 'rgba(0, 0, 0, 0)' || fundo === 'transparent')
    ) {
      alvo = alvo.parentElement;
      fundo = getComputedStyle(alvo).backgroundColor;
    }
    const canais = fundo
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map(Number);
    const linear = canais.map(canal => {
      const n = canal / 255;
      return n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4;
    });
    return {
      cor: fundo,
      luminancia: 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2],
    };
  });

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
    const { luminancia } = await luminanciaComputada(frame, '#app');
    expect(luminancia).toBeLessThan(0.1);
  });

  test('sem `darkMode` configurado e SO CLARO, o widget abre claro', async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: 'light' });
    const frame = await abrirWidget(page, { theme: 'auto' });

    const raiz = await lerRaizDoWidget(frame);
    expect(raiz.temClasseDark).toBe(false);
    expect(raiz.colorScheme).toBe('light');

    const { luminancia } = await luminanciaComputada(frame, '#app');
    expect(luminancia).toBeGreaterThan(0.5);
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
    const depoisDaTroca = await luminanciaComputada(frame, '#app');
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
