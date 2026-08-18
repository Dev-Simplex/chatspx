/**
 * Mecanismo de aceite do bloco 2.14 — degradação do launcher, em NAVEGADOR.
 *
 * ACEITE (§2.2): «Bloqueando o bundle no devtools, o link alternativo aparece».
 *
 * `page.route(...).abort()` é o bloqueio do devtools, automatizado: a
 * requisição do `sdk.js` morre antes de chegar ao servidor, exatamente como um
 * bloqueador de conteúdo faz.
 *
 * As asserções perguntam ao motor o valor COMPUTADO — visibilidade, cor,
 * posição — em vez de conferir a folha de estilo e concluir. Ler regra é
 * raciocínio; perguntar ao Chromium é medição, e esta base já foi mordida três
 * vezes por catch-all de CSS que passava verde em jsdom.
 *
 * Config próprio (`spec/e2e/fallback/playwright.config.js`) e servidor em porta
 * EFÊMERA dentro do processo do teste: este arquivo não encosta no harness de
 * porta fixa do widget (3038/3999/8899).
 */
const { test, expect } = require('@playwright/test');
const { iniciarServidor } = require('./harness/hostServer');

let servidor;

test.beforeAll(async () => {
  servidor = await iniciarServidor();
});

test.afterAll(async () => {
  await servidor?.fechar();
});

const bloquearBundle = page =>
  page.route('**/packs/js/sdk.js', rota => rota.abort('blockedbyclient'));

const linkDe = page => page.locator('#cw-fallback-link');

test.describe('2.14 — o bundle falhou', () => {
  test('o link alternativo aparece, visível e clicável', async ({ page }) => {
    await bloquearBundle(page);
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });

    const link = linkDe(page);
    await expect(link).toBeVisible();
    await expect(link).toHaveText('Falar por outro canal');

    // Visível para o Playwright não basta: um elemento de 0 px de altura ou
    // com `opacity: 0` pode passar por "visível" em algumas checagens. Aqui
    // perguntamos ao motor a geometria e a opacidade computadas.
    const medido = await link.evaluate(elemento => {
      const caixa = elemento.getBoundingClientRect();
      const estilo = getComputedStyle(elemento);
      return {
        largura: caixa.width,
        altura: caixa.height,
        opacidade: Number(estilo.opacity),
        visibilidade: estilo.visibility,
        posicao: estilo.position,
      };
    });

    expect(medido.largura).toBeGreaterThan(80);
    expect(medido.altura).toBeGreaterThan(28);
    expect(medido.opacidade).toBeCloseTo(1, 2);
    expect(medido.visibilidade).toBe('visible');
    expect(medido.posicao).toBe('fixed');
  });

  test('aponta para a página própria do chat quando nada foi configurado', async ({
    page,
  }) => {
    await bloquearBundle(page);
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });

    const href = await linkDe(page).getAttribute('href');
    expect(href).toBe(
      `${servidor.origem}/widget?website_token=${servidor.tokenDeTeste}`
    );

    await expect(linkDe(page)).toHaveAttribute('target', '_blank');
    await expect(linkDe(page)).toHaveAttribute('rel', 'noopener noreferrer');
  });

  test('o link leva mesmo a algum lugar', async ({ page, context }) => {
    await bloquearBundle(page);
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });

    const [aba] = await Promise.all([
      context.waitForEvent('page'),
      linkDe(page).click(),
    ]);
    await expect(aba.getByRole('heading')).toHaveText('Chat em aba própria');
  });

  test('o cliente pode apontar para o canal dele', async ({ page }) => {
    await bloquearBundle(page);
    const alvo = 'https://wa.me/5511999999999';
    await page.goto(
      `${servidor.origem}/?fallbackUrl=${encodeURIComponent(alvo)}&fallbackLabel=${encodeURIComponent('Chamar no WhatsApp')}`,
      { waitUntil: 'domcontentloaded' }
    );

    await expect(linkDe(page)).toHaveAttribute('href', alvo);
    await expect(linkDe(page)).toHaveText('Chamar no WhatsApp');
  });

  test('respeita o lado configurado do launcher', async ({ page }) => {
    await bloquearBundle(page);
    await page.goto(`${servidor.origem}/?position=left`, {
      waitUntil: 'domcontentloaded',
    });

    const caixa = await linkDe(page).evaluate(elemento => {
      const r = elemento.getBoundingClientRect();
      return { esquerda: r.left, direita: window.innerWidth - r.right };
    });
    expect(caixa.esquerda).toBeLessThan(caixa.direita);
  });

  test('o link nasce com a marca legível, não com texto invisível', async ({
    page,
  }) => {
    // As cores saem de `WidgetTokens` no servidor — a mesma fonte WCAG que
    // pinta o launcher. Aqui medimos o que o Chromium REALMENTE computou, que
    // é o único jeito de saber se algum `!important` de terceiro atropelou.
    await bloquearBundle(page);
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });

    const cores = await linkDe(page).evaluate(elemento => {
      const estilo = getComputedStyle(elemento);
      return { fundo: estilo.backgroundColor, texto: estilo.color };
    });

    const canais = valor =>
      valor
        .match(/[\d.]+/g)
        .slice(0, 3)
        .map(Number);
    const luminancia = cor =>
      canais(cor)
        .map(c => {
          const n = c / 255;
          return n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4;
        })
        .reduce((soma, v, i) => soma + [0.2126, 0.7152, 0.0722][i] * v, 0);

    const claro = Math.max(luminancia(cores.fundo), luminancia(cores.texto));
    const escuro = Math.min(luminancia(cores.fundo), luminancia(cores.texto));
    const razao = (claro + 0.05) / (escuro + 0.05);

    // WCAG 1.4.3 AA para texto grande/negrito é 3:1; o alvo do projeto para
    // texto sobre a marca é 4.5:1 (ver `WidgetTokens::READABLE_TARGET`).
    expect(razao).toBeGreaterThanOrEqual(4.5);
  });
});

test.describe('2.14 — o bundle carregou normalmente', () => {
  test('o link alternativo NÃO aparece', async ({ page }) => {
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });

    await expect
      .poll(() => page.evaluate(() => Boolean(window.$chatwoot)), {
        timeout: 10000,
      })
      .toBe(true);

    await expect(linkDe(page)).toHaveCount(0);
  });

  test('um SDK que chega DEPOIS do prazo retira o link', async ({ page }) => {
    // O falso positivo do prazo em rede lenta: o link já apareceu e o bundle
    // chega em seguida. Sem o `hide()` de `entrypoints/sdk.js`, o visitante
    // ficaria com o link pendurado ao lado de um widget que funciona.
    await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });
    await expect
      .poll(() => page.evaluate(() => Boolean(window.$chatwoot)), {
        timeout: 10000,
      })
      .toBe(true);

    // Força o estado "prazo estourou": pede o link com o SDK já presente e
    // depois simula a chegada dele.
    await page.evaluate(() => {
      const anterior = window.$chatwoot;
      delete window.$chatwoot;
      window.chatwootFallback.show();
      window.$chatwoot = anterior;
    });
    await expect(linkDe(page)).toHaveCount(1);

    await page.evaluate(() =>
      window.chatwootSDK.run({ websiteToken: 'x', baseUrl: 'y' })
    );
    await expect(linkDe(page)).toHaveCount(0);
  });
});
