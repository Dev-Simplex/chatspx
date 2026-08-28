/**
 * Bloco 3.17, segunda metade — «o `bg-white` sem `dark:` do `ArticleViewer`».
 *
 * ── O QUE ESTE ARQUIVO DECIDE ───────────────────────────────────────────────
 *
 * O relatório definitivo (`ESTADO-BLOCOS-DEFINITIVO.md`, linha 133) descreve
 * `ArticleViewer.vue:13` como `<div class="bg-white h-full">` — uma cor CRAVADA,
 * que no tema escuro deixaria a tela de artigo branca dentro do painel escuro.
 * Naquela árvore o diagnóstico estava certo.
 *
 * Nesta base ele ENVELHECEU: o delta da v4.16.2 (bloco 0.2) já trocou a linha
 * para `bg-n-solid-1`. E `n-solid-1` NÃO é `bg-white` com outro nome —
 * `theme/colors.js:239` a define como `rgb(var(--solid-1) / <alpha-value>)`, e
 * `--solid-1` é REAPONTADA por tema em `widget/assets/scss/_tokens_values.scss`
 * (`255 255 255` no claro, `23 23 26` no escuro), aplicada por `_tokens.scss`
 * em `:root` e `.dark`. A indireção pela custom property é o par `dark:`.
 *
 * Acrescentar `dark:bg-n-solid-1` ao lado de `bg-n-solid-1` seria escrever a
 * MESMA declaração duas vezes: no escuro as duas resolvem para a mesma cor.
 * Por isso o bloco fecha sem tocar o componente — e é por isso que a prova
 * precisa existir, porque "não mudei nada" só vale acompanhado de medição.
 *
 * ── POR QUE EM NAVEGADOR, E NÃO POR LEITURA DO FONTE ────────────────────────
 *
 * Porque a pergunta é de CASCATA, e cascata não se lê: se resolve. As classes
 * `n-*` já ficaram presas numa cor nesta base — `dashboard/.../_wa-skin.scss`
 * força `.bg-n-solid-1 { background-color: #111b21 !important }` no escuro, e
 * `!important` vence variável (é a razão de existir o namespace `wp` em
 * `theme/colors.js:337`). Aquele arquivo não entra no bundle do widget, mas
 * "não entra" é outra afirmação de leitura. O que decide é a cor que o
 * Chromium computou, e é só isso que se assere aqui.
 *
 * A rota é alcançada pelo roteador vivo (`name: 'article-viewer'`,
 * `widget/router.js:38`), sem `query.link`: sem URL o `IframeLoader` não monta
 * `<iframe>` nenhum (`v-if="url"`), então nenhuma requisição externa sai e o
 * fixture anti-erro não tem 404 de ambiente para reclamar. A `div` que este
 * teste mede é a raiz do `ArticleViewer`, que existe independente disso.
 */
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const ANCORA_HOME = 'Estamos conectados.';

// A raiz do `ArticleViewer` — a `div` da linha 13, a que pinta a tela de
// artigo.
//
// ⚠️ ANCORADA NA ESTRUTURA, NÃO NA CLASSE, e isso foi uma correção medida. A
// primeira versão usava `#app .bg-n-solid-1.h-full`. Ela ficava vermelha na
// sabotagem — mas pelo motivo ERRADO: com a linha em `bg-white` o seletor
// simplesmente não casa, e o teste morre em `toBeAttached()` sem nunca ler cor
// nenhuma. Isso prova que a classe sumiu, não que a TELA ficou branca no
// escuro — que é o defeito que o bloco descreve. Um teste de cor que falha
// antes de medir cor não mediu nada.
//
// `pb-1/2` é a âncora porque é única em todo `app/javascript/` (só
// `IframeLoader.vue:58`), e o `ArticleViewer` é o pai dele. Assim a superfície
// continua encontrável com QUALQUER classe de fundo — inclusive a errada.
const ANCORA_DO_LOADER = '.pb-1\\/2';

// A verificação de classe vira asserção PRÓPRIA, em vez de virar seletor. As
// duas perguntas são diferentes e merecem falhar separado: "a cor computada
// está certa?" e "a cor veio de token ou está cravada no componente?".
const CLASSES_DE_COR_CRAVADA =
  /\b(bg-white|bg-black|bg-\[#|bg-(gray|slate|zinc|neutral|stone)-\d)/;

const abrirArtigo = async (page, { theme }) => {
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
  await expect(frame.getByText(ANCORA_HOME, { exact: true })).toBeVisible();

  await frame.locator('body').evaluate(async () => {
    await window.WOOT_WIDGET.$router.replace({ name: 'article-viewer' });
  });

  await expect(frame.locator(ANCORA_DO_LOADER)).toHaveCount(1);

  return frame;
};

// Mede o que o motor REALMENTE aplicou. Devolve a cor crua, o alfa e a
// luminância relativa WCAG — a mesma fórmula de `darkMode.spec.js`, de
// propósito: as duas superfícies do painel têm de ser julgadas pela mesma
// régua.
const medirSuperficie = frame =>
  frame.locator(ANCORA_DO_LOADER).evaluate(loader => {
    // O pai do `IframeLoader` É a `div` da linha 13 do `ArticleViewer`.
    const elemento = loader.parentElement;
    const fundo = getComputedStyle(elemento).backgroundColor;
    const canais = fundo.match(/[\d.]+/g).map(Number);
    const alfa = canais.length > 3 ? canais[3] : 1;
    const linear = canais.slice(0, 3).map(canal => {
      const n = canal / 255;
      return n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4;
    });
    const caixa = elemento.getBoundingClientRect();
    return {
      cor: fundo,
      alfa,
      classe: elemento.className,
      area: caixa.width * caixa.height,
      luminancia: 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2],
    };
  });

// As duas guardas contra o falso verde que já mordeu `darkMode.spec.js`:
//
//   · alfa — superfície transparente devolve luminância 0, que PASSA a
//     asserção de "escuro" pelo motivo errado. `rgba(0,0,0,0)` não é preto: é
//     ausência de medição.
//   · área — elemento colapsado (`h-full` sem cadeia de altura) tem cor
//     computada mas não pinta pixel nenhum. Medir isso seria medir nada.
const exigirSuperficieReal = medida => {
  expect(
    medida.alfa,
    `superfície transparente (${medida.cor}) — não há cor computada para medir`
  ).toBeGreaterThan(0.99);
  expect(
    medida.area,
    `superfície colapsada (${medida.area}px²) — não pinta pixel para medir`
  ).toBeGreaterThan(0);
};

test.describe('3.17 — o ArticleViewer acompanha o tema', () => {
  test('no tema CLARO a tela de artigo é clara', async ({ page }) => {
    const frame = await abrirArtigo(page, { theme: 'light' });

    const medida = await medirSuperficie(frame);
    exigirSuperficieReal(medida);

    // `--solid-1: 255 255 255` no claro — a MESMA cor que o `bg-white` de
    // antes produzia. É esta metade que garante que a troca do 0.2 não foi
    // regressão nenhuma no tema em que a tela já estava certa.
    expect(medida.cor).toBe('rgb(255, 255, 255)');
    expect(medida.luminancia).toBeGreaterThan(0.5);
  });

  test('no tema ESCURO a tela de artigo é escura', async ({ page }) => {
    const frame = await abrirArtigo(page, { theme: 'dark' });

    const medida = await medirSuperficie(frame);
    exigirSuperficieReal(medida);

    // `--solid-1: 23 23 26` no escuro. É ESTA asserção que o `bg-white`
    // descrito no relatório reprova — e foi assim que se mediu que a linha do
    // relatório envelheceu: com a árvore em `bg-white`, este teste falha
    // apontando `rgb(255, 255, 255)`.
    expect(medida.cor).toBe('rgb(23, 23, 26)');
    expect(medida.luminancia).toBeLessThan(0.1);
  });

  test('a tela de artigo não contradiz o painel que a contém', async ({
    page,
  }) => {
    // O defeito que o título do bloco descreve não é "a cor X está errada" —
    // é "a tela de artigo discorda do resto do painel". Esta asserção é a que
    // sobrevive a uma futura troca de paleta: os dois lados podem mudar de
    // valor, mas nunca podem divergir de tema.
    const frame = await abrirArtigo(page, { theme: 'dark' });

    const artigo = await medirSuperficie(frame);
    exigirSuperficieReal(artigo);

    const painel = await frame
      .locator('#app > div')
      .first()
      .evaluate(elemento => getComputedStyle(elemento).backgroundColor);

    const painelEscuro = painel
      .match(/[\d.]+/g)
      .slice(0, 3)
      .every(canal => Number(canal) < 64);

    expect(
      painelEscuro,
      `painel em ${painel} — o artigo mediu ${artigo.cor}`
    ).toBe(true);
    expect(artigo.luminancia).toBeLessThan(0.1);
  });

  test('o fundo vem de token, não de cor cravada no componente', async ({
    page,
  }) => {
    // A cor certa pelo mecanismo errado ainda é dívida: `bg-white` acerta o
    // tema claro por coincidência e só quebra no escuro. Esta asserção falha
    // no momento em que alguém volta a cravar cor, mesmo que o tema claro
    // continue verde — é a guarda que protege a decisão deste bloco de ser
    // desfeita sem ninguém perceber.
    const frame = await abrirArtigo(page, { theme: 'light' });
    const medida = await medirSuperficie(frame);

    expect(
      CLASSES_DE_COR_CRAVADA.test(medida.classe),
      `a raiz do ArticleViewer voltou a cravar cor: "${medida.classe}"`
    ).toBe(false);
    expect(medida.classe).toContain('bg-n-solid-1');
  });
});
