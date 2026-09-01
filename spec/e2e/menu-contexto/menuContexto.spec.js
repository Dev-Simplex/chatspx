/* eslint-disable no-undef */
/**
 * E2E — MENU DE CONTEXTO DA CONVERSA (regressao do recorte do redesenho).
 *
 * ── O QUE ESTE TESTE TRAVA ─────────────────────────────────────────────────────
 *
 * A reescrita de `ConversationCard.vue` para `script setup` deixou o cartao
 * EMITINDO `contextmenu` sem ninguem montando o menu. Em toda a arvore,
 * `ConversationContextMenu` so era referenciado por um `.vue.backup`. Sumiram da
 * lista, sem erro nenhum no console: atribuir agente, atribuir time, marcar como
 * lida/nao lida, prioridade, rotulo, apagar conversa — e o alfinete de fixar.
 *
 * Medido em 01/09/2026 contra hmlchat, com o bundle publicado (sem o bloco):
 *   raizes de ContextMenu apos o clique direito .... 0
 *   itens do menu presentes na tela ................ 0 de 8
 *   clique esquerdo navegou ........................ nao (URL inalterada)
 *
 * ── POR QUE NAO E VITEST ───────────────────────────────────────────────────────
 *
 * Um `shallowMount` do cartao passaria com o menu quebrado: o defeito nao esta no
 * cartao isolado, esta na AUSENCIA do bloco que monta o menu, e o menu vive num
 * `Teleport` para o `body`, aberto por evento `contextmenu` do navegador, com
 * submenus que so existem no `:hover` do CSS. E "surtir efeito" e o backend
 * respondendo. Nada disso e observavel no jsdom.
 *
 * ── ESCRITA DE VERDADE, E DESFEITA ─────────────────────────────────────────────
 *
 * Os dois cenarios de efeito GRAVAM no backend e depois voltam ao estado
 * anterior, sempre na mesma conversa (a primeira da lista). O `_helpers.js` tem
 * uma trava de host: fora de homologacao, o cenario falha em vez de gravar.
 */
const { test, expect } = require('@playwright/test');
const {
  TEMPO_PADRAO,
  abrirListaDeConversas,
  abrirMenuNoCartao,
  contaDaSessao,
  escolherNoSubmenu,
  exigirPermissaoDeEscrita,
  itemDoMenu,
  menuDeContexto,
  servirBundleLocal,
  temAlgumaPrioridade,
  temNaoLida,
  temPrioridadeUrgente,
} = require('./_helpers');

// Os rotulos vem do pt_BR de verdade (`conversation.json` / `chatlist.json`).
// Escritos aqui LITERAIS de proposito: se alguem trocar a chave por outra, ou
// deixar a chave crua vazar para a tela, o teste cai — que e o ponto.
// "Excluir conversa" so aparece para administrador (`isAdmin` no menu), entao o
// usuario de QA precisa ser administrador da conta — e e.
//
// "Marcar como resolvida" e "Adiar" sao deterministicos aqui porque a lista esta
// no filtro "Aberta": o menu esconde a acao igual ao status atual. Fora deste
// filtro os dois deixariam de valer.
//
// "Marcar como nao lida" so aparece em conversa SEM nao lidas — por isso os
// cenarios de item abrem o menu num cartao escolhido por esse criterio. Na
// conversa COM nao lidas o item vira "Marcar como lida", e ele some de quem nao e
// o atribuido (o backend recusa a escrita; ver `canMarkAsRead`).
const ITENS_ESPERADOS = [
  'Fixar no topo',
  'Marcar como não lida',
  'Marcar como resolvida',
  'Adiar',
  'Prioridade',
  'Atribuir etiqueta',
  'Atribuir Agente',
  'Atribuir time',
  'Abrir em nova aba',
  'Copiar link da conversa',
  'Excluir conversa',
];

let contaId;

/** O nome do contato no cartao — usado como identidade estavel da linha. */
const nomeDoCartao = cartao =>
  cartao.locator('h4.conversation--user').first().innerText();

/** O primeiro cartao em que o marcador procurado NAO esta presente. */
const primeiroCartaoSem = async (cartoes, marcador) => {
  const total = await cartoes.count();
  const presencas = await Promise.all(
    Array.from({ length: total }, (_, i) => marcador(cartoes.nth(i)).count())
  );
  const indice = presencas.findIndex(quantidade => quantidade === 0);
  return indice === -1 ? null : cartoes.nth(indice);
};

/** Todos os rotulos visiveis no menu aberto. */
const exigirItens = (menu, rotulos, sufixo = '') =>
  Promise.all(
    rotulos.map(rotulo =>
      expect(
        itemDoMenu(menu, rotulo),
        `item "${rotulo}" no menu${sufixo}`
      ).toBeVisible()
    )
  );

test.beforeEach(async ({ page, baseURL }) => {
  expect(
    baseURL,
    'E2E_BASE_URL precisa apontar para a instalacao'
  ).toBeTruthy();
  if (process.env.E2E_VITE_DIR) {
    await servirBundleLocal(page, process.env.E2E_VITE_DIR, baseURL);
  }
  // A sessao ja veio do `storageState` (um login por rodada, no globalSetup).
  contaId = contaDaSessao();
});

test.describe('Menu de contexto da conversa', () => {
  test('abre no clique direito e traz todos os itens — tema claro', async ({
    page,
  }) => {
    const cartoes = await abrirListaDeConversas(page, contaId);
    // O tema e medido, nao suposto: um teste "no claro" que rodasse no escuro
    // continuaria verde e nao valeria como cobertura de tema nenhum.
    await expect
      .poll(() => page.evaluate(() => document.body.classList.contains('dark')))
      .toBe(false);

    const alvo = await primeiroCartaoSem(cartoes, temNaoLida);
    test.skip(!alvo, 'Nenhuma conversa lida na lista carregada.');
    const menu = await abrirMenuNoCartao(page, alvo);

    await exigirItens(menu, ITENS_ESPERADOS);

    // Nenhuma chave crua vazou para a tela.
    await expect(menu).not.toContainText('CONVERSATION.');
    await expect(menu).not.toContainText('CHAT_LIST.');
  });

  test('abre no clique direito e traz todos os itens — tema escuro', async ({
    page,
  }) => {
    const cartoes = await abrirListaDeConversas(page, contaId);
    await expect
      .poll(() => page.evaluate(() => document.body.classList.contains('dark')))
      .toBe(true);

    const alvo = await primeiroCartaoSem(cartoes, temNaoLida);
    test.skip(!alvo, 'Nenhuma conversa lida na lista carregada.');
    const menu = await abrirMenuNoCartao(page, alvo);

    await exigirItens(menu, ITENS_ESPERADOS, ' (escuro)');
    await expect(menu).not.toContainText('CONVERSATION.');
  });

  test('fecha ao clicar fora', async ({ page }) => {
    const cartoes = await abrirListaDeConversas(page, contaId);
    await abrirMenuNoCartao(page, cartoes.first());

    await page.mouse.click(1200, 500);
    await expect(menuDeContexto(page)).toHaveCount(0, {
      timeout: TEMPO_PADRAO,
    });
  });

  test('marcar como nao lida surte efeito e volta atras', async ({
    page,
    baseURL,
  }) => {
    exigirPermissaoDeEscrita(baseURL);
    const cartoes = await abrirListaDeConversas(page, contaId);

    // Precisa de uma conversa SEM "nao lida", senao o item oferecido e o inverso.
    const alvo = await primeiroCartaoSem(cartoes, temNaoLida);
    test.skip(
      !alvo,
      'Todas as conversas carregadas ja estao nao lidas; nada a marcar.'
    );
    const identidade = await nomeDoCartao(alvo);

    const escritas = [];
    page.on('response', resposta => {
      if (/\/conversations\/\d+\/unread$/.test(resposta.url())) {
        escritas.push({ url: resposta.url(), status: resposta.status() });
      }
    });

    let menu = await abrirMenuNoCartao(page, alvo);
    await itemDoMenu(menu, 'Marcar como não lida').click();

    // Efeito no BACKEND: a chamada saiu e o servidor aceitou.
    await expect.poll(() => escritas.length, { timeout: TEMPO_PADRAO }).toBe(1);
    expect(escritas[0].status, JSON.stringify(escritas[0])).toBe(200);
    // Efeito na TELA: o cartao passou a exibir o marcador de nao lida.
    await expect(temNaoLida(alvo)).toBeVisible({ timeout: TEMPO_PADRAO });

    // A lista e viva: se ela reordenou, o `nth` de antes aponta para OUTRA
    // conversa e tudo daqui para baixo mediria a errada.
    expect(
      await nomeDoCartao(alvo),
      'a lista reordenou no meio do cenario'
    ).toBe(identidade);

    // Desfaz: a conversa e real e nao pode ficar marcada por causa do teste.
    menu = await abrirMenuNoCartao(page, alvo);
    await itemDoMenu(menu, 'Marcar como lida').click();
    await expect(temNaoLida(alvo)).toHaveCount(0, { timeout: TEMPO_PADRAO });
  });

  test('prioridade surte efeito e volta atras', async ({ page, baseURL }) => {
    exigirPermissaoDeEscrita(baseURL);
    const cartoes = await abrirListaDeConversas(page, contaId);

    // SEM prioridade nenhuma, nao apenas sem a urgente: se a conversa ja tivesse
    // "alta", o passo de desfazer ("Nenhuma") apagaria a prioridade de verdade.
    const alvo = await primeiroCartaoSem(cartoes, temAlgumaPrioridade);
    test.skip(!alvo, 'Nenhuma conversa sem prioridade na lista carregada.');
    const identidade = await nomeDoCartao(alvo);

    const escritas = [];
    page.on('response', resposta => {
      if (/\/conversations\/\d+\/toggle_priority$/.test(resposta.url())) {
        escritas.push({ status: resposta.status() });
      }
    });

    let menu = await abrirMenuNoCartao(page, alvo);
    await escolherNoSubmenu(menu, 'Prioridade', 'Urgente');

    await expect.poll(() => escritas.length, { timeout: TEMPO_PADRAO }).toBe(1);
    expect(escritas[0].status, JSON.stringify(escritas[0])).toBe(200);
    await expect(temPrioridadeUrgente(alvo)).toBeVisible({
      timeout: TEMPO_PADRAO,
    });

    expect(
      await nomeDoCartao(alvo),
      'a lista reordenou no meio do cenario'
    ).toBe(identidade);

    menu = await abrirMenuNoCartao(page, alvo);
    await escolherNoSubmenu(menu, 'Prioridade', 'Nenhuma');
    await expect(temPrioridadeUrgente(alvo)).toHaveCount(0, {
      timeout: TEMPO_PADRAO,
    });
  });

  test('o cartao abre a conversa no clique esquerdo', async ({ page }) => {
    // Mesma regressao, mesmo arquivo: o cartao reescrito emitia `click` e
    // nenhum pai escutava, entao clicar numa conversa nao fazia nada.
    const cartoes = await abrirListaDeConversas(page, contaId);
    const antes = page.url();

    await cartoes.first().click();
    await expect
      .poll(() => page.url(), { timeout: TEMPO_PADRAO })
      .toMatch(/\/conversations\/\d+/);
    expect(page.url()).not.toBe(antes);
  });
});
