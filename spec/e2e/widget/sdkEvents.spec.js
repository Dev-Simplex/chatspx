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
    'CHATWOOT_MESSAGE_SENT',
    'CHATWOOT_CSAT_SUBMITTED',
    'CHATWOOT_CAMPAIGN_SHOWN',
  ];
  const faltando = exigidos.filter(nome => !mapa[nome]);
  if (faltando.length) {
    throw new Error(
      `constantes ausentes em sdkEvents.js: ${faltando.join(', ')}`
    );
  }
  return mapa;
};

// O ID DO COMPOSER, lido da FONTE, pela mesma razão dos nomes de evento acima —
// e por uma cicatriz concreta: este arquivo usava `#chat-input`, que NÃO existe
// no widget. Esse id vive em
// `dashboard/modules/widget-preview/components/WidgetFooter.vue`, ou seja, na
// MAQUETE do painel; o campo real do widget é `#w-composer-campo`
// (`widget/ui/WComposer.vue:70`). O seletor órfão fazia o teste morrer de
// timeout em vez de medir o evento que ele promete medir.
//
// Ler da fonte impede a reincidência: se alguém renomear o id no componente e
// não aqui, este helper levanta na hora, nomeando o arquivo — em vez de o teste
// esperar 8 s por um elemento que ninguém mais desenha.
const idDoComposer = () => {
  const arquivo = path.resolve(
    __dirname,
    '../../../app/javascript/widget/ui/WComposer.vue'
  );
  const fonte = fs.readFileSync(arquivo, 'utf8');
  const achado = fonte.match(/<textarea\s+id="([\w-]+)"/);
  if (!achado) {
    throw new Error(
      `nao achei o id do <textarea> em widget/ui/WComposer.vue — ` +
        `o composer do widget mudou de forma e este teste precisa ser relido`
    );
  }
  return `#${achado[1]}`;
};

const COMPOSER = idDoComposer();

const EVENTOS = nomesDeEvento();
const ORDEM_DO_ACEITE = [
  EVENTOS.CHATWOOT_OPENED,
  EVENTOS.CHATWOOT_CONVERSATION_CREATED,
  EVENTOS.CHATWOOT_PRECHAT_SUBMITTED,
  EVENTOS.CHATWOOT_LEAD_IDENTIFIED,
];

const EMAIL_DIGITADO = 'ana.prado@exemplo.com.br';
const NOME_DIGITADO = 'Ana Prado';

const MENSAGEM_DE_CSAT = {
  id: 207,
  content: 'Que nota você dá para o atendimento?',
  content_type: 'input_csat',
  created_at: 1736942400,
  message_type: 3,
  status: 'sent',
  content_attributes: {},
  conversation_id: 314,
};

// `time_on_page: 0` faz o temporizador da campanha disparar no proximo tick, em
// vez de o teste esperar segundos reais por um `setTimeout` do produto.
const CAMPANHA = {
  id: 12,
  title: 'Teaser determinístico',
  trigger_rules: { time_on_page: 0, url: `${HOST_URL}/` },
};

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

const responder = (route, corpo) =>
  route.fulfill({
    status: 200,
    contentType: 'application/json; charset=utf-8',
    body: JSON.stringify(corpo),
  });

/**
 * Visitante NOVO: sem conversa anterior e sem mensagens.
 *
 * `mensagens` permite semear a conversa (o CSAT precisa de uma mensagem
 * `input_csat` renderizada para haver o que clicar).
 */
const rotasDeVisitanteNovo = async (page, mensagens = []) => {
  // Padrao por EXPRESSAO REGULAR, e nao por glob: o `*` do glob do Playwright
  // nao atravessa `/`, entao `**/widget/messages*` deixava passar
  // `/widget/messages/207` (o PATCH do CSAT) e `/widget/conversations/toggle_typing`.
  // As duas caiam no harness, que responde 500 a rota que nao conhece — e a
  // fixture reprova por erro de console, mascarando o que o teste media.
  await page.route(/\/api\/v1\/widget\/conversations/, route => {
    const { pathname } = new URL(route.request().url());
    const criando =
      route.request().method() === 'POST' &&
      pathname.endsWith('/widget/conversations');
    return responder(route, criando ? CONVERSA_CRIADA : {});
  });
  await page.route(/\/api\/v1\/widget\/messages/, route => {
    const metodo = route.request().method();
    if (metodo === 'POST') {
      return responder(route, {
        id: 2001,
        conversation_id: CONVERSA_CRIADA.id,
        content: 'Mensagem do visitante',
        content_type: 'text',
        created_at: 1736942400,
        message_type: 0,
        status: 'sent',
      });
    }
    if (metodo === 'PATCH' || metodo === 'PUT') return responder(route, {});
    return responder(route, {
      payload: mensagens,
      meta: { contact_last_seen_at: 0 },
    });
  });
};

/** Leva o painel para a tela de conversa, que e onde vivem composer e CSAT. */
const irParaMensagens = async frame => {
  await frame
    .locator('body')
    .evaluate(async () =>
      window.WOOT_WIDGET.$router.replace({ name: 'messages' })
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
  test('a mensagem do visitante sai como chatwoot:message-sent (T-C3.4)', async ({
    page,
  }) => {
    await escutarEventos(page, [
      EVENTOS.CHATWOOT_CONVERSATION_CREATED,
      EVENTOS.CHATWOOT_MESSAGE_SENT,
    ]);
    await rotasDeVisitanteNovo(page);
    const frame = await abrirWidget(page);
    await irParaMensagens(frame);

    // `toBeVisible` antes de digitar: se o composer sumir do desenho, a falha
    // diz "o campo não está visível" em vez de "timeout ao preencher", que é o
    // que fazia o seletor órfão parecer lentidão.
    await expect(frame.locator(COMPOSER)).toBeVisible();
    await frame.locator(COMPOSER).fill('Mensagem do visitante');
    await frame.locator(COMPOSER).press('Enter');

    await expect
      .poll(async () => (await eventosObservados(page)).map(e => e.nome), {
        timeout: 30000,
      })
      // Sem pre-chat a conversa nasce COM a mensagem: o fato "conversa criada"
      // precede o fato "mensagem enviada", mesmo tendo os dois vindo do mesmo
      // POST.
      .toEqual([
        EVENTOS.CHATWOOT_CONVERSATION_CREATED,
        EVENTOS.CHATWOOT_MESSAGE_SENT,
      ]);

    const observados = await eventosObservados(page);
    expect(observados[1].detalhe).toEqual({
      conversation_id: CONVERSA_CRIADA.id,
    });
  });

  test('a nota do CSAT sai como chatwoot:csat-submitted (T-C3.5)', async ({
    page,
  }) => {
    await escutarEventos(page, [EVENTOS.CHATWOOT_CSAT_SUBMITTED]);
    await rotasDeVisitanteNovo(page, [MENSAGEM_DE_CSAT]);
    const frame = await abrirWidget(page);
    await irParaMensagens(frame);

    await expect(
      frame.getByText('Que nota você dá para o atendimento?', { exact: true })
    ).toBeVisible();
    // A ultima carinha e a nota 5 (CSAT_RATINGS em shared/constants/messages.js).
    await frame.locator('.emoji-button').last().click();

    await expect
      .poll(() => eventosObservados(page), { timeout: 30000 })
      .toEqual([
        { nome: EVENTOS.CHATWOOT_CSAT_SUBMITTED, detalhe: { rating: 5 } },
      ]);
  });

  test('a campanha exibida sai como chatwoot:campaign-shown (T-C3.6)', async ({
    page,
  }) => {
    await escutarEventos(page, [EVENTOS.CHATWOOT_CAMPAIGN_SHOWN]);
    await rotasDeVisitanteNovo(page);
    await page.route('**/api/v1/widget/campaigns*', route =>
      responder(route, [CAMPANHA])
    );

    // O widget fica FECHADO de proposito: campanha so e exibida para quem ainda
    // nao abriu o chat, e `startCampaign` recusa com o painel aberto.
    await page.goto(`${HOST_URL}/?scenario=home&theme=light`, {
      waitUntil: 'domcontentloaded',
    });
    await expect
      .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
        timeout: 30000,
      })
      .toBe(true);

    await expect
      .poll(() => eventosObservados(page), { timeout: 30000 })
      .toEqual([
        {
          nome: EVENTOS.CHATWOOT_CAMPAIGN_SHOWN,
          detalhe: { campaign_id: CAMPANHA.id },
        },
      ]);
  });
});
