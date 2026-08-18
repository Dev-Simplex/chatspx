const fs = require('node:fs');
const path = require('node:path');
const { test, expect } = require('../fixtures');

/**
 * O ACEITE DO BLOCO 5.04, medido em navegador de verdade.
 *
 * "A ordem `widget_opened → conversation_created → prechat_submitted →
 * lead_identified` é observável por `addEventListener` em navegador real."
 *
 * Não é um teste de unidade com duble de `postMessage`: aqui rodam o SDK real
 * no documento do host (porta 8899), o painel real dentro do iframe (porta
 * 3999) e a ponte de `postMessage` entre os dois, com verificação de origem.
 * O que o teste escuta é exatamente o que o GTM do cliente escutaria.
 *
 * ── SOBRE 127.0.0.1 ──────────────────────────────────────────────────────────
 *
 * A cicatriz da execução manda não validar por `127.0.0.1` porque o
 * `Rack::Attack` tem safelist para localhost e metade do caminho de requisição
 * não executa. Aqui isso NÃO se aplica: não há Rails no caminho. Os três
 * servidores do harness são Node, a API do widget é servida por
 * `harness/widget-server.mjs`, e este teste ainda intercepta as três rotas que
 * usa. Nenhum middleware do Rails participa — não há o que a safelist pudesse
 * pular. O que o teste mede é a ponte JS, e ela é a mesma em qualquer host.
 */

const HOST_URL = 'http://127.0.0.1:8899';

// Os nomes vêm da FONTE ÚNICA, lidos do arquivo. Repeti-los aqui faria o teste
// concordar consigo mesmo depois de um rename — que é justamente o defeito que
// o aceite manda impedir.
const nomesDeEvento = () => {
  const arquivo = path.resolve(
    __dirname,
    '../../../app/javascript/widget/constants/sdkEvents.js'
  );
  const fonte = fs.readFileSync(arquivo, 'utf8');
  const mapa = Object.fromEntries(
    [...fonte.matchAll(/export const (CHATWOOT_\w+) = '([^']+)'/g)].map(m => [
      m[1],
      m[2],
    ])
  );
  const exigidos = [
    'CHATWOOT_OPENED',
    'CHATWOOT_CONVERSATION_CREATED',
    'CHATWOOT_PRECHAT_SUBMITTED',
    'CHATWOOT_LEAD_IDENTIFIED',
    'CHATWOOT_RESET_COMPLETED',
  ];
  const faltando = exigidos.filter(nome => !mapa[nome]);
  if (faltando.length) {
    throw new Error(
      `constantes ausentes em sdkEvents.js: ${faltando.join(', ')}`
    );
  }
  return mapa;
};

const EVENTOS = nomesDeEvento();
const ORDEM_DO_ACEITE = [
  EVENTOS.CHATWOOT_OPENED,
  EVENTOS.CHATWOOT_CONVERSATION_CREATED,
  EVENTOS.CHATWOOT_PRECHAT_SUBMITTED,
  EVENTOS.CHATWOOT_LEAD_IDENTIFIED,
];

const EMAIL_DIGITADO = 'ana.prado@exemplo.com.br';
const NOME_DIGITADO = 'Ana Prado';

const CONVERSA_CRIADA = {
  id: 314,
  inbox_id: 7,
  status: 'open',
  contact_last_seen_at: 0,
  contact: {
    id: 19,
    name: NOME_DIGITADO,
    email: EMAIL_DIGITADO,
    phone_number: null,
  },
  messages: [
    {
      id: 1001,
      content: 'Quero um orçamento',
      content_type: 'text',
      created_at: 1736942400,
      message_type: 0,
      status: 'sent',
      conversation_id: 314,
    },
  ],
};

/** Escuta TODOS os eventos do contrato antes de o SDK carregar. */
const escutarEventos = async (page, nomes) => {
  await page.addInitScript(listaDeNomes => {
    window.wootEventosDoContrato = [];
    listaDeNomes.forEach(nome => {
      window.addEventListener(nome, evento => {
        window.wootEventosDoContrato.push({
          nome,
          detalhe: evento.detail ?? null,
        });
      });
    });
  }, nomes);
};

/** Visitante NOVO: sem conversa anterior e sem mensagens. */
const rotasDeVisitanteNovo = async page => {
  await page.route('**/api/v1/widget/conversations*', route => {
    const corpo = route.request().method() === 'POST' ? CONVERSA_CRIADA : {};
    return route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify(corpo),
    });
  });
  await page.route('**/api/v1/widget/messages*', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify({ payload: [], meta: {} }),
    })
  );
};

const abrirWidget = async page => {
  await page.goto(`${HOST_URL}/?scenario=prechat-form&theme=light`, {
    waitUntil: 'domcontentloaded',
  });
  await expect
    .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
      timeout: 30000,
    })
    .toBe(true);

  const frame = page.frameLocator('#chatwoot_live_chat_widget');
  await expect(frame.locator('#app')).toBeVisible();
  await expect
    .poll(
      () =>
        frame
          .locator('body')
          .evaluate(() => Boolean(window.WOOT_WIDGET?.$router)),
      { timeout: 30000 }
    )
    .toBe(true);

  // Clique no lançador de verdade, no documento do host — é o gesto que produz
  // `chatwoot:opened`. Chamar `$chatwoot.toggle('open')` daria o mesmo evento
  // por um caminho que o visitante nunca percorre.
  await page.locator('.woot-widget-bubble').first().click();
  await expect(page.locator('#cw-widget-holder')).not.toHaveClass(/woot--hide/);
  return frame;
};

const eventosObservados = page =>
  page.evaluate(() => window.wootEventosDoContrato);

test.describe('contrato de eventos de window (bloco 5.04)', () => {
  test('a ordem do aceite é observável por addEventListener', async ({
    page,
  }) => {
    await escutarEventos(page, ORDEM_DO_ACEITE);
    await rotasDeVisitanteNovo(page);
    const frame = await abrirWidget(page);

    await frame
      .locator('body')
      .evaluate(async () =>
        window.WOOT_WIDGET.$router.replace({ name: 'prechat-form' })
      );
    await expect(
      frame.getByText('Conte um pouco sobre você.', { exact: true })
    ).toBeVisible();

    await frame.locator('input[name="fullName"]').fill(NOME_DIGITADO);
    await frame.locator('input[name="emailAddress"]').fill(EMAIL_DIGITADO);
    await frame.locator('textarea[name="message"]').fill('Quero um orçamento');
    await frame.getByRole('button', { name: 'Iniciar Conversa' }).click();

    await expect
      .poll(async () => (await eventosObservados(page)).length, {
        timeout: 30000,
      })
      .toBe(ORDEM_DO_ACEITE.length);

    const observados = await eventosObservados(page);
    expect(observados.map(evento => evento.nome)).toEqual(ORDEM_DO_ACEITE);
  });

  test('cada evento chega uma vez só e com o payload do contrato', async ({
    page,
  }) => {
    await escutarEventos(page, ORDEM_DO_ACEITE);
    await rotasDeVisitanteNovo(page);
    const frame = await abrirWidget(page);

    await frame
      .locator('body')
      .evaluate(async () =>
        window.WOOT_WIDGET.$router.replace({ name: 'prechat-form' })
      );
    await frame.locator('input[name="fullName"]').fill(NOME_DIGITADO);
    await frame.locator('input[name="emailAddress"]').fill(EMAIL_DIGITADO);
    await frame.locator('textarea[name="message"]').fill('Quero um orçamento');
    await frame.getByRole('button', { name: 'Iniciar Conversa' }).click();

    await expect
      .poll(async () => (await eventosObservados(page)).length, {
        timeout: 30000,
      })
      .toBe(ORDEM_DO_ACEITE.length);

    const observados = await eventosObservados(page);
    const porNome = Object.fromEntries(
      observados.map(evento => [evento.nome, evento.detalhe])
    );

    // Nenhum nome repetido: 4 eventos escutados, 4 recebidos, 4 nomes distintos.
    expect(new Set(observados.map(e => e.nome)).size).toBe(observados.length);

    expect(porNome[EVENTOS.CHATWOOT_CONVERSATION_CREATED]).toEqual({
      conversation_id: 314,
      inbox_id: 7,
    });
    expect(porNome[EVENTOS.CHATWOOT_PRECHAT_SUBMITTED]).toEqual({
      fields: ['fullName', 'emailAddress'],
    });
    expect(porNome[EVENTOS.CHATWOOT_LEAD_IDENTIFIED]).toEqual({
      conversation_id: 314,
      identifiers: ['email'],
    });

    // A REGRA DURA: nome de campo sim, valor nunca. O `window` do site é
    // legível por qualquer script de terceiro na página do cliente.
    const serializado = JSON.stringify(observados);
    expect(serializado).not.toContain(EMAIL_DIGITADO);
    expect(serializado).not.toContain(NOME_DIGITADO);
  });

  test('reset() deixa de ser mudo e confirma a conclusão (T-I4.5)', async ({
    page,
  }) => {
    await escutarEventos(page, [EVENTOS.CHATWOOT_RESET_COMPLETED]);
    await rotasDeVisitanteNovo(page);
    await abrirWidget(page);

    await page.evaluate(() => window.$chatwoot.reset());

    await expect
      .poll(async () => (await eventosObservados(page)).map(e => e.nome), {
        timeout: 30000,
      })
      .toEqual([EVENTOS.CHATWOOT_RESET_COMPLETED]);
  });
});
