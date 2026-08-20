/**
 * O ACEITE DE ROLAGEM DO BLOCO 2.04, num navegador de verdade.
 *
 *   «Mensagem chegando com o visitante 300 px acima **não** o arranca.»
 *
 * ── Por que aqui, e não só em jsdom ──────────────────────────────────────────
 *
 * Porque "300 px acima" é geometria, e jsdom não tem layout: `scrollHeight`,
 * `clientHeight` e `scrollTop` são zero e ficam zero. O spec de unidade
 * (`widget/components/specs/rolagem.spec.js`) dita a geometria e mede a
 * DECISÃO; ele pega a regra errada. Este mede a regra certa aplicada ao
 * elemento certo — e é o único que pegaria, por exemplo, o ouvinte de `scroll`
 * ligado no elemento que não rola, que foi exatamente o que o bloco mudou:
 * antes a raiz era quem rolava; agora ela é a superfície e quem rola é o filho.
 *
 * ── Como a lista fica alta o bastante para rolar ─────────────────────────────
 *
 * O harness serve 4 mensagens curtas, que não enchem o painel. A rota é
 * interceptada com 40 — mesma técnica do cenário `rich-types`, e pelo mesmo
 * motivo: servir pela rota vale para qualquer carga (a inicial e a tardia),
 * enquanto injetar no store depois de montado perde a corrida com a recarga
 * que o widget faz quando a configuração do SDK chega.
 */
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const FROZEN_EPOCH = 1736942400;
const DISTANCIA_DO_FIM = 300;

const MUITAS_MENSAGENS = Array.from({ length: 40 }, (_, i) => ({
  id: 500 + i,
  content: `Mensagem determinística número ${i + 1} da lista longa.`,
  content_type: 'text',
  created_at: FROZEN_EPOCH - (40 - i) * 60,
  message_type: i % 2,
  status: 'sent',
  ...(i % 2
    ? {
        sender: {
          id: 7,
          name: 'Marina Lima',
          available_name: 'Marina Lima',
          availability_status: 'online',
        },
      }
    : {}),
}));

const abrirConversaLonga = async page => {
  await page.route('**/api/v1/widget/messages*', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify({
        payload: MUITAS_MENSAGENS,
        meta: { contact_last_seen_at: FROZEN_EPOCH - 3000 },
      }),
    })
  );
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto(`${HOST_URL}/?scenario=messages&theme=light`, {
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
          .evaluate(() =>
            Boolean(window.WOOT_WIDGET?.$router && window.WOOT_WIDGET?.$store)
          ),
      { timeout: 30000 }
    )
    .toBe(true);
  await page.evaluate(() => window.$chatwoot.toggle('open'));
  await frame.locator('body').evaluate(async () => {
    await window.WOOT_WIDGET.$router.replace({ name: 'messages' });
  });
  await expect(
    frame.getByText('Mensagem determinística número 40 da lista longa.', {
      exact: true,
    })
  ).toBeVisible();
  return frame;
};

const geometria = frame =>
  frame.locator('.conversation-wrap').evaluate(el => ({
    scrollTop: Math.round(el.scrollTop),
    distanciaDoFim: Math.round(
      el.scrollHeight - el.scrollTop - el.clientHeight
    ),
    rola: el.scrollHeight > el.clientHeight,
  }));

// Uma mensagem nova, entregando pelo mesmo caminho do ActionCable: a mutação do
// store. Não é atalho — é o ponto exato em que a mensagem chega ao widget.
//
// ⚠️ O `_elemento` NÃO é decoração: `locator.evaluate(fn, arg)` chama `fn` com o
// ELEMENTO na primeira posição e o argumento na segunda. Sem ele, `id` recebia
// o `<body>`, as duas mensagens iam para o store com a MESMA chave
// (`[object HTMLBodyElement]`) e a segunda sobrescrevia a primeira — o widget
// contava 1 onde chegaram 2, e o defeito parecia ser do contador.
const chegarMensagem = (frame, id) =>
  frame.locator('body').evaluate((_elemento, idNovo) => {
    window.WOOT_WIDGET.$store.commit('conversation/pushMessageToConversation', {
      id: idNovo,
      content: 'Chegou enquanto o visitante lia o histórico.',
      content_type: 'text',
      created_at: 1736942400,
      message_type: 1,
      status: 'sent',
      sender: { id: 7, name: 'Marina Lima', available_name: 'Marina Lima' },
    });
  }, id);

// As CHAVES do store, que é onde o defeito acima aparecia. Contador certo com
// store errado seria verde por coincidência: se as duas mensagens colidissem na
// mesma chave, chegariam duas e existiria uma, e um contador quebrado que
// dissesse "1" pareceria correto. Medir as chaves separa as duas coisas.
const idsNoStore = frame =>
  frame
    .locator('body')
    .evaluate(() =>
      Object.keys(window.WOOT_WIDGET.$store.state.conversation.conversations)
    );

test('mensagem nova com o visitante 300 px acima NÃO o arranca', async ({
  page,
}) => {
  const frame = await abrirConversaLonga(page);
  const lista = frame.locator('.conversation-wrap');

  // Sanidade antes da medição: se a lista não rolasse, o teste passaria por
  // não haver de onde arrancar ninguém.
  const inicial = await geometria(frame);
  expect(inicial.rola).toBe(true);

  await lista.evaluate((el, folga) => {
    el.scrollTop = el.scrollHeight - el.clientHeight - folga;
  }, DISTANCIA_DO_FIM);
  await expect
    .poll(async () => (await geometria(frame)).distanciaDoFim)
    .toBe(DISTANCIA_DO_FIM);
  const antes = await geometria(frame);

  await chegarMensagem(frame, 901);
  await expect(
    frame.getByText('Chegou enquanto o visitante lia o histórico.', {
      exact: true,
    })
  ).toBeAttached();

  const depois = await geometria(frame);
  expect(depois.scrollTop).toBe(antes.scrollTop);
});

test('e o caminho de volta aparece, com o contador', async ({ page }) => {
  const frame = await abrirConversaLonga(page);
  const lista = frame.locator('.conversation-wrap');

  await expect(frame.locator('.conversation--descer')).toHaveCount(0);

  await lista.evaluate((el, folga) => {
    el.scrollTop = el.scrollHeight - el.clientHeight - folga;
  }, DISTANCIA_DO_FIM);
  // Esperar a posição ANTES de mandar a mensagem não é cerimônia: `scroll` não
  // é síncrono. O navegador o entrega na próxima oportunidade de renderização,
  // então escrever `scrollTop` e comitar no store em seguida faz a mensagem
  // chegar com o componente ainda achando que o visitante está no fim — e o
  // contador sai um a menos. Foi assim que este teste falhou na primeira
  // execução, e o defeito era do teste.
  await expect
    .poll(async () => (await geometria(frame)).distanciaDoFim)
    .toBe(DISTANCIA_DO_FIM);

  await chegarMensagem(frame, 902);
  await chegarMensagem(frame, 903);

  // Chegaram DUAS, e são duas de verdade no store — não uma sobrescrevendo a
  // outra. Sem esta linha o "(2)" abaixo poderia ser lido como correto num
  // cenário em que só uma mensagem existe.
  const ids = await idsNoStore(frame);
  expect(ids).toContain('902');
  expect(ids).toContain('903');

  const botao = frame.locator('.conversation--descer button');
  await expect(botao).toBeVisible();
  // O contador no NOME ACESSÍVEL, não só no pixel.
  await expect(botao).toHaveAccessibleName(
    'Ir para as mensagens mais recentes (2)'
  );

  await botao.click();
  await expect
    .poll(async () => (await geometria(frame)).distanciaDoFim)
    .toBeLessThanOrEqual(80);
  await expect(frame.locator('.conversation--descer')).toHaveCount(0);
});

test('mensagem nova com o visitante NO FIM continua rolando', async ({
  page,
}) => {
  // O par do primeiro teste. Sem ele, "não arranca" seria satisfeito por um
  // widget que simplesmente parou de rolar — que é pior que o defeito.
  const frame = await abrirConversaLonga(page);
  await expect
    .poll(async () => (await geometria(frame)).distanciaDoFim)
    .toBeLessThanOrEqual(80);

  await chegarMensagem(frame, 904);
  await expect(
    frame.getByText('Chegou enquanto o visitante lia o histórico.', {
      exact: true,
    })
  ).toBeVisible();

  await expect
    .poll(async () => (await geometria(frame)).distanciaDoFim)
    .toBeLessThanOrEqual(80);
});
