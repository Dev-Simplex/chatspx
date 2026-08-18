/**
 * ACEITE do bloco 4.03, medido em navegador de verdade:
 * **"fluxo de 4 campos conclui em 375 px sem scroll horizontal"**.
 *
 * 375 px é a largura do menor telefone que ainda importa (iPhone SE). Barra
 * horizontal num formulário de captura não é feiura: é o campo que o visitante
 * não alcança, e portanto o lead que não chega.
 *
 * A medição é do LAYOUT real — Vue real, `woot.scss` real, Tailwind gerado pelo
 * config do widget. Nenhum CSS de teste. E é feita em TRÊS momentos, porque a
 * largura pode estourar em qualquer um deles:
 *   1. formulário recém-desenhado;
 *   2. com a mensagem de erro mais longa visível (texto novo dentro da bolha);
 *   3. com os quatro campos preenchidos e o botão liberado.
 *
 * Não usa `networkidle`: espera a âncora de conteúdo (o rótulo do 4º campo).
 */
const { test, expect } = require('@playwright/test');

const LARGURA = 375;

let harness;

test.beforeAll(async () => {
  const { iniciar } = await import('./harness.mjs');
  harness = await iniciar();
});

test.afterAll(async () => {
  await harness?.encerrar();
});

const larguraDeRolagem = page =>
  page.evaluate(() => ({
    documento: document.documentElement.scrollWidth,
    corpo: document.body.scrollWidth,
    janela: window.innerWidth,
  }));

test.describe('4.03 — fluxo de captura de 4 campos em 375 px', () => {
  test.use({ viewport: { width: LARGURA, height: 720 } });

  test('conclui sem barra de rolagem horizontal em nenhum momento', async ({
    page,
  }) => {
    await page.goto(harness.url);

    // Âncora de conteúdo forte: o rótulo do QUARTO campo, que só existe se o
    // formulário inteiro montou.
    await expect(page.getByLabel('CPF')).toBeVisible({ timeout: 60000 });

    const inicial = await larguraDeRolagem(page);
    expect(inicial.janela).toBe(LARGURA);
    expect(inicial.documento).toBeLessThanOrEqual(LARGURA);
    expect(inicial.corpo).toBeLessThanOrEqual(LARGURA);

    // (2) O pior caso de texto: erro de telefone, que é a mensagem mais longa do
    // conjunto ("Telefone inválido. Inclua o DDI, como +55.").
    await page.getByLabel('WhatsApp com DDI').fill('11999998888');
    await page.getByLabel('WhatsApp com DDI').blur();
    await expect(page.getByRole('alert').first()).toBeVisible();

    const comErro = await larguraDeRolagem(page);
    expect(comErro.documento).toBeLessThanOrEqual(LARGURA);
    expect(comErro.corpo).toBeLessThanOrEqual(LARGURA);

    // (3) Preenchimento completo — e a máscara do 4.03 aplicada no blur.
    await page.getByLabel('Nome completo').fill('Walisson Ricieri');
    await page.getByLabel('E-mail corporativo').fill('walisson@simplex.com.br');
    await page.getByLabel('WhatsApp com DDI').fill('+5511999998888');
    await page.getByLabel('WhatsApp com DDI').blur();
    await page.getByLabel('CPF').fill('12345678909');
    await page.getByLabel('CPF').blur();

    await expect(page.getByLabel('CPF')).toHaveValue('123.456.789-09');

    const preenchido = await larguraDeRolagem(page);
    expect(preenchido.documento).toBeLessThanOrEqual(LARGURA);
    expect(preenchido.corpo).toBeLessThanOrEqual(LARGURA);

    // CONCLUI: o botão libera e a submissão acontece com os quatro valores.
    const enviar = page.getByTestId('capture-submit');
    await expect(enviar).toBeEnabled();
    await enviar.click();

    const enviado = await page.evaluate(() => window.__captureSubmitted);
    expect(enviado).toEqual([
      { name: 'nome', value: 'Walisson Ricieri' },
      { name: 'email', value: 'walisson@simplex.com.br' },
      // MEDIDO, e vale registrar: a máscara `phone` do 3.13 devolve o valor
      // INTACTO quando ele começa com `+` — quem digita DDI está informando um
      // número internacional, e reformatá-lo quebraria quem cola do exterior
      // (`maskPhone`, brMasks.js). Como o validador `phone` EXIGE o DDI
      // (`isPhoneWithDialCode`), o par mask+validator nesse campo nunca
      // reformata: quem prova a máscara aqui é o CPF, logo abaixo.
      { name: 'whatsapp', value: '+5511999998888' },
      { name: 'cpf', value: '123.456.789-09' },
    ]);
  });

  test('nenhum campo transborda a bolha — cada um cabe na largura da tela', async ({
    page,
  }) => {
    await page.goto(harness.url);
    await expect(page.getByLabel('CPF')).toBeVisible({ timeout: 60000 });

    const excedentes = await page.evaluate(largura => {
      const alvos = [...document.querySelectorAll('input, select, textarea, button')];
      return alvos
        .map(elemento => ({
          nome: elemento.name || elemento.type || elemento.tagName,
          direita: Math.round(elemento.getBoundingClientRect().right),
        }))
        .filter(medida => medida.direita > largura);
    }, LARGURA);

    expect(excedentes).toEqual([]);
  });

  /**
   * ESTE TESTE NASCEU DE UMA SABOTAGEM QUE NÃO FALHOU.
   *
   * A primeira versão do aceite media só `scrollWidth` do documento e a caixa de
   * cada campo. Sabotei de propósito o botão (devolvendo o `whitespace-nowrap`
   * que o `.button` do widget traz) e o teste **passou mesmo assim**: o botão é
   * `block`, então a CAIXA dele continua com 100% da largura — quem estoura é o
   * TEXTO dentro dela, e nem o `scrollWidth` do documento nem o `getBoundingClientRect`
   * enxergam isso.
   *
   * Um aceite que não falha quando o defeito existe não é aceite, é decoração.
   * A medição certa é por elemento: `scrollWidth > clientWidth` significa
   * conteúdo maior do que a caixa que o contém.
   */
  test('nenhum elemento tem conteúdo maior que a própria caixa (o teste que a sabotagem exigiu)', async ({
    page,
  }) => {
    await page.goto(harness.url);
    await expect(page.getByLabel('CPF')).toBeVisible({ timeout: 60000 });

    const transbordando = await page.evaluate(() =>
      [...document.querySelectorAll('#app *')]
        .map(elemento => ({
          nome: elemento.getAttribute('data-testid') || elemento.tagName,
          texto: (elemento.textContent || '').trim().slice(0, 40),
          conteudo: elemento.scrollWidth,
          caixa: elemento.clientWidth,
        }))
        // `clientWidth` é 0 em elemento sem caixa (inline); +1 absorve o
        // arredondamento sub-pixel do layout, que não é transbordo.
        .filter(medida => medida.caixa > 0 && medida.conteudo > medida.caixa + 1)
    );

    expect(transbordando).toEqual([]);
  });
});
