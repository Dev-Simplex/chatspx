const { test, expect } = require('../fixtures');

/**
 * Os cenários que provam o fixture anti-erro (bloco 0.11).
 *
 * ESTE ARQUIVO NÃO É PARA PASSAR INTEIRO. Metade dele existe para REPROVAR: são sabotagens,
 * e uma sabotagem que passa significa que o fixture não está medindo. Quem decide se o
 * resultado está certo é `fixture-antierro.check.mjs`, que roda este arquivo e confere,
 * cenário por cenário, quem reprovou e com qual mensagem.
 *
 * NÃO DEPENDE DE PORTA NENHUMA — nem de servidor. Tudo é `page.route` e `setContent`. A
 * versão anterior herdava os três `webServer` das portas 3038/3999/8899 (slot único, disputado
 * por várias trilhas) só para provar um fixture; o mecanismo que verifica a rede de segurança
 * não pode ser o que mais briga por recurso.
 */

const PAGINA = 'http://sabotagem.local/';

const abrirPagina = async page => {
  await page.route('http://sabotagem.local/**', route =>
    route.fulfill({ contentType: 'text/html', body: '<main>sabotagem</main>' })
  );
  await page.goto(PAGINA);
};

// ── DEVEM REPROVAR ──────────────────────────────────────────────────────────────────────

test('REPROVA: console.error', async ({ page }) => {
  await abrirPagina(page);
  await page.evaluate(() => {
    // eslint-disable-next-line no-console
    console.error('sabotagem-console-marcador');
  });
});

test('REPROVA: pageerror', async ({ page }) => {
  const erro = page.waitForEvent('pageerror');
  await abrirPagina(page);
  await page.evaluate(() => {
    setTimeout(() => {
      throw new Error('sabotagem-pageerror-marcador');
    }, 0);
  });
  await erro;
});

test('REPROVA: HTTP 500 nomeando método e URL', async ({ page }) => {
  await abrirPagina(page);
  // registrada DEPOIS da genérica: o Playwright consulta as rotas da última para a primeira
  await page.route('**/api/sabotagem-500', route =>
    route.fulfill({ status: 500, body: 'erro' })
  );
  await page.evaluate(() => fetch('/api/sabotagem-500').catch(() => {}));
  await page.waitForTimeout(200);
});

test('REPROVA: falha de rede', async ({ page }) => {
  const falhou = page.waitForEvent('requestfailed');
  await page.goto('http://127.0.0.1:1/sabotagem-rede').catch(() => {});
  await falhou;
});

// O `context.on('page')`: erro numa janela nova é erro igual, e sem observá-la ninguém o vê.
test('REPROVA: console.error em janela NOVA', async ({ page, context }) => {
  await abrirPagina(page);
  const nova = await context.newPage();
  await nova.route('http://sabotagem.local/**', route =>
    route.fulfill({ contentType: 'text/html', body: '<main>popup</main>' })
  );
  await nova.goto(PAGINA);
  await nova.evaluate(() => {
    // eslint-disable-next-line no-console
    console.error('sabotagem-popup-marcador');
  });
  await nova.close();
});

test.describe('escape declarado que NÃO acontece', () => {
  test.use({
    errosEsperados: { padroes: [/sabotagem-que-nunca-ocorre/] },
  });

  // Escape que sobrevive ao cenário que o justificava é como a lista vira decoração.
  test('REPROVA: errosEsperados obsoleto', async ({ page }) => {
    await abrirPagina(page);
  });
});

test.describe('escape amplo demais', () => {
  test.use({
    errosEsperados: { padroes: [/.*/] },
  });

  test('REPROVA: padrão catch-all é recusado', async ({ page }) => {
    await abrirPagina(page);
  });
});

test.describe('a armadilha da tupla do Playwright', () => {
  // DOIS padroes num array cru: o Playwright le como `[valor, options]` e entrega so o
  // primeiro, descartando o segundo em silencio. O fixture detecta e NOMEIA — porque escape
  // que perde padrao sem avisar deixa o teste vermelho por um erro que o autor achou que
  // tinha declarado. Ver o cabecalho de `normalizarEscape` em `spec/e2e/fixtures.js`.
  test.use({ errosEsperados: [/sabotagem-a/, /sabotagem-b/] });

  test('REPROVA: array cru com dois padroes e detectado', async ({ page }) => {
    await abrirPagina(page);
  });
});

// ── DEVEM PASSAR ────────────────────────────────────────────────────────────────────────

test('PASSA: página limpa', async ({ page }) => {
  await abrirPagina(page);
  await expect(page.locator('main')).toHaveText('sabotagem');
});

test.describe('escape legítimo, por cenário e por mensagem', () => {
  test.use({
    errosEsperados: { padroes: [/sabotagem-escape-legitimo/] },
  });

  test('PASSA: o erro que o próprio cenário provoca', async ({ page }) => {
    await abrirPagina(page);
    await page.evaluate(() => {
      // eslint-disable-next-line no-console
      console.error('sabotagem-escape-legitimo');
    });
  });
});
