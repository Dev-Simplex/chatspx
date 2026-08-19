/**
 * A SUPERFÍCIE DA LISTA, medida no app real — bloco 2.04, e a linha que sobrou
 * do 2.03.
 *
 * O 2.03 tirou a sombra do balão dizendo que *"a separação vem do par de
 * superfícies e, no escuro, de borda de 1 px"*. Isso é uma promessa sobre duas
 * cores que só existem juntas quando o app está montado: `--w-surface-sunken`
 * chega por um `<style scoped>` de `ConversationWrap.vue`, e o balão por
 * utilitárias de `TextContent.vue`. Não dá para reproduzir isso em HTML estático
 * — o `data-v-*` do scoped não existe fora do componente — e é por isso que esta
 * medição vive no E2E e não no check de Chromium do 2.03.
 *
 * O que ele trava é o que o visitante enxerga: **existe aresta entre o balão e a
 * lista, nos dois temas, agora que não há mais sombra?**
 *
 * As razões medidas são IMPRESSAS, não só comparadas. Elas são baixas, e
 * baixas de propósito — o relatório do bloco explica por quê. Um teste que
 * escondesse o número deixaria a decisão parecer um acidente.
 */
/* eslint-disable no-console -- as razões medidas são a saída útil deste spec,
   lidas por quem roda e coladas no relatório do bloco. */
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';

const luminancia = ([r, g, b]) => {
  const f = c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const contraste = (a, b) => {
  const [l1, l2] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
};
const rgb = s =>
  s
    .match(/[\d.]+/g)
    .slice(0, 3)
    .map(Number);

const abrir = async (page, tema) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto(`${HOST_URL}/?scenario=messages&theme=${tema}`, {
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
    frame.getByText('Mensagem determinística para o cenário.', { exact: true })
  ).toBeVisible();
  return frame;
};

const medir = frame =>
  frame.locator('.conversation--container').evaluate(container => {
    const balao = container.querySelector('.chat-bubble.agent');
    const estiloBalao = getComputedStyle(balao);
    const lista = container.querySelector('.conversation-wrap');
    const estiloLista = getComputedStyle(lista);
    const pilula = container.querySelector('.w-date-separator__pilula');
    const caixaPilula = pilula.getBoundingClientRect();
    return {
      // ── As três mudanças que os snapshots do 2.04 registram ───────────────
      // Elas estão aqui porque baseline defendida só por imagem depende de
      // alguém olhar; defendida por medição, se defende sozinha. Cada uma tem
      // o seu exame lá embaixo.
      padding: [
        estiloLista.paddingTop,
        estiloLista.paddingLeft,
        estiloLista.paddingRight,
        estiloLista.paddingBottom,
      ],
      pilula: {
        raio: getComputedStyle(pilula).borderRadius,
        altura: Math.round(caixaPilula.height),
        largura: Math.round(caixaPilula.width),
        fundo: getComputedStyle(pilula).backgroundColor,
        alturaDaLinha: getComputedStyle(pilula).lineHeight,
        etiqueta: pilula.tagName,
      },
      superficie: getComputedStyle(container).backgroundColor,
      balao: estiloBalao.backgroundColor,
      sombraDoBalao: estiloBalao.boxShadow,
      bordaDoBalao: estiloBalao.borderTopWidth,
      corDaBorda: estiloBalao.borderTopColor,
      // A textura é um `::before` do contêiner. Se ela sumir, o
      // `background-color` continua lá e nada quebra — mas o desenho vai
      // embora, e é o único jeito de perceber isso é medindo a máscara.
      mascara: getComputedStyle(container, '::before').maskImage,
      tintaDaTextura: getComputedStyle(container, '::before').backgroundColor,
      opacidadeDaTextura: Number(
        getComputedStyle(container, '::before').opacity
      ),
    };
  });

// O traço da textura onde a máscara é OPACA, composto sobre a superfície. É o
// pior caso do desenho: onde o rabisco é mais forte. `getComputedStyle` não
// entrega isso pronto — a composição acontece no compositor —, então ela é
// refeita aqui com os três valores computados que a produzem.
const compor = (superficie, tinta, opacidade) =>
  superficie.map((canal, i) => canal * (1 - opacidade) + tinta[i] * opacidade);

['light', 'dark'].forEach(tema => {
  test(`2.04 — a lista tem superfície própria e o balão se separa dela (${tema})`, async ({
    page,
  }) => {
    const frame = await abrir(page, tema);
    const m = await medir(frame);
    const razao = contraste(rgb(m.superficie), rgb(m.balao));

    console.log(
      `[superfície ${tema}] lista=${m.superficie}  balão=${m.balao}  ` +
        `contraste=${razao.toFixed(4)}:1  borda=${m.bordaDoBalao} ${m.corDaBorda}`
    );

    // 1. A lista pinta superfície própria — não é mais transparente com um
    //    `background-image` fazendo o papel de fundo.
    expect(m.superficie).not.toBe('rgba(0, 0, 0, 0)');
    // 2. E o balão NÃO é a mesma cor que ela: sem sombra, cores iguais
    //    significariam um balão invisível.
    expect(m.balao).not.toBe(m.superficie);
    // 3. A sombra continua fora — é o aceite do 2.03, reconferido com o app
    //    montado e não só em HTML de laboratório.
    expect(m.sombraDoBalao).toBe('none');
    // 4. A textura é máscara, e a tinta dela vem do token — por isso ela muda
    //    de cor entre os temas sem trocar de arquivo.
    expect(m.mascara).toContain('chat-spx-texture.webp');
  });
});

test('2.03 — no ESCURO o balão ganha a borda de 1 px que substitui a sombra', async ({
  page,
}) => {
  const escuro = await medir(await abrir(page, 'dark'));
  expect(escuro.bordaDoBalao).toBe('1px');
  expect(escuro.corDaBorda).not.toBe('rgba(0, 0, 0, 0)');
});

test('2.03 — no CLARO a borda não desenha, porque o par de superfícies basta', async ({
  page,
}) => {
  // A largura continua 1 px nos dois temas de propósito: com `border-box` isso
  // mantém a MESMA caixa, e trocar de tema não move layout. O que muda é só a
  // cor, que no claro cai no fallback transparente.
  const claro = await medir(await abrir(page, 'light'));
  expect(claro.bordaDoBalao).toBe('1px');
  expect(claro.corDaBorda).toBe('rgba(0, 0, 0, 0)');
});

test('2.04 — a tinta da textura inverte entre os temas, com um arquivo só', async ({
  page,
}) => {
  const claro = await medir(await abrir(page, 'light'));
  const escuro = await medir(await abrir(page, 'dark'));

  expect(claro.tintaDaTextura).not.toBe(escuro.tintaDaTextura);
  expect(claro.mascara).toBe(escuro.mascara);
});

// ── O aceite de "textura LEVE", com número ───────────────────────────────────
//
// "Leve" precisa de régua, senão é adjetivo. A régua é a textura que já estava
// no ar e passou pelos 20 snapshots: medida nos baselines, o traço dela contra
// a superfície dá 1,284:1 no claro e 1,251:1 no escuro. O teto de 1,30 é esse
// número com folga de arredondamento.
//
// Sem este teste, subir `--w-texture-opacity` seria uma edição de uma linha que
// deixa a lista mais suja e não acusa em lugar nenhum: os testes de classe
// continuam verdes, e o snapshot que pegaria isso é justamente o que se
// regravaria junto.
const TETO_DO_TRACO = 1.3;

['light', 'dark'].forEach(tema => {
  test(`2.04 — a textura é leve: o traço não passa de ${TETO_DO_TRACO}:1 (${tema})`, async ({
    page,
  }) => {
    const m = await medir(await abrir(page, tema));
    const traco = compor(
      rgb(m.superficie),
      rgb(m.tintaDaTextura),
      m.opacidadeDaTextura
    );
    const razao = contraste(rgb(m.superficie), traco);

    console.log(
      `[textura ${tema}] superfície=${m.superficie}  opacidade=${m.opacidadeDaTextura}  ` +
        `traço=rgb(${traco.map(Math.round).join(', ')})  contraste=${razao.toFixed(3)}:1`
    );

    expect(m.opacidadeDaTextura).toBeGreaterThan(0);
    expect(
      razao,
      `o traço da textura mede ${razao.toFixed(3)}:1 contra a superfície; ` +
        `o teto de "leve" é ${TETO_DO_TRACO}:1`
    ).toBeLessThanOrEqual(TETO_DO_TRACO);
  });
});

// ── CONDIÇÃO 1 DA REGRAVAÇÃO DOS 8 SNAPSHOTS ─────────────────────────────────
//
// Os 8 baselines de `messages` e `rich-types` mudaram por TRÊS causas, e só
// três. Enquanto elas viviam apenas na imagem, "a mudança é a esperada" era
// palavra de quem regravou. Aqui cada uma vira número, medido do app montado.
//
// A quarta causa — a intensidade da textura — já tem o seu exame acima, e foi
// justamente ela que apareceu ERRADA quando se olhou os PNG.

test('2.04 — a lista pinta a superfície tokenizada, não o fundo antigo', async ({
  page,
}) => {
  // CAUSA 1 dos snapshots. Antes: branco quase puro no claro e quase preto no
  // escuro, vindos de um `background-image` com véu. Agora `--w-surface-sunken`,
  // que sai de `--slate-3` e resolve sozinha nos dois temas.
  const claro = await medir(await abrir(page, 'light'));
  const escuro = await medir(await abrir(page, 'dark'));

  expect(claro.superficie).toBe('rgb(240, 240, 243)');
  expect(escuro.superficie).toBe('rgb(33, 34, 37)');
});

['light', 'dark'].forEach(tema => {
  test(`2.04 — o separador é uma PÍLULA, e sem altura fixa (${tema})`, async ({
    page,
  }) => {
    // CAUSA 2. O separador compartilhado desenhava a data solta entre duas
    // linhas horizontais, com `h-[50px] leading-[50px]` — altura fixa em
    // elemento com texto, que é o que quebra quando o visitante aumenta a fonte
    // do navegador.
    const m = await medir(await abrir(page, tema));
    // eslint-disable-next-line no-console
    console.log(
      `[pílula ${tema}] ${m.pilula.largura}×${m.pilula.altura} ` +
        `raio=${m.pilula.raio} fundo=${m.pilula.fundo} ` +
        `line-height=${m.pilula.alturaDaLinha} <${m.pilula.etiqueta}>`
    );

    // Pílula: o raio é maior que a metade da altura, que é a definição
    // geométrica de "as pontas são semicírculos". Verificar `border-radius:
    // 9999px` seria verificar a escrita; isto verifica a forma.
    const raio = Number.parseFloat(m.pilula.raio);
    expect(raio).toBeGreaterThanOrEqual(m.pilula.altura / 2);
    // Fundo próprio — sem ele a "pílula" seria só texto centralizado.
    expect(m.pilula.fundo).not.toBe('rgba(0, 0, 0, 0)');
    // E a altura fixa de 50 px se foi, junto com o `line-height` que a
    // acompanhava. A caixa agora é o texto mais o padding.
    expect(m.pilula.altura).toBeLessThan(50);
    expect(m.pilula.alturaDaLinha).not.toBe('50px');
    // `<time>`, porque é data: o leitor de tela anuncia como etiqueta em vez de
    // parágrafo solto no meio da conversa.
    expect(m.pilula.etiqueta).toBe('TIME');
  });
});

test('2.04 — o padding da lista é 16/12/8, e não o 32/8/8 de antes', async ({
  page,
}) => {
  // CAUSA 3, e a que desloca TODAS as linhas verticalmente nos 8 baselines —
  // por isso o diff parece maior do que a mudança é.
  const m = await medir(await abrir(page, 'light'));
  // eslint-disable-next-line no-console
  console.log(`[padding] ${m.padding.join(' / ')}`);

  const [topo, esquerda, direita, base] = m.padding;
  expect(topo).toBe('16px');
  expect(esquerda).toBe('12px');
  expect(direita).toBe('12px');
  expect(base).toBe('8px');
});
