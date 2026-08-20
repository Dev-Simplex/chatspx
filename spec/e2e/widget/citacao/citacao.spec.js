/**
 * Aceite de APARÊNCIA e de NOME ACESSÍVEL da citação de fonte — bloco 6.03.
 *
 * Os 15 testes de unidade de `citationList.spec.js` provam a LÓGICA (quando há citação,
 * quando não há, o que vira link). Eles rodam em jsdom, e jsdom não resolve cascata nem
 * custom property: ele confirma que a classe está lá, nunca que a cor chegou. Este
 * arquivo mede no Chromium as duas coisas que só existem no navegador:
 *
 *   1. A COR RESOLVIDA e a razão de contraste sobre o fundo REAL da conversa, nos dois
 *      temas. `color: rgb(var(--slate-11))` com o token indefinido é função inválida, e
 *      o Chromium cai no preto herdado — teste de unidade verde, texto ilegível na tela.
 *      Por isso a primeira asserção de cada tema é que o token RESOLVEU.
 *
 *   2. O NOME ACESSÍVEL calculado pelo próprio navegador, lido da árvore de
 *      acessibilidade (`page.accessibility.snapshot`) e não de um matcher de biblioteca.
 *      O aceite é que o emoji do título do cliente fique na TELA e saia do NOME.
 *
 * NÃO usa `127.0.0.1` por preguiça: a página é servida por um Vite local em porta
 * efêmera e não atravessa o Rails, então não há `Rack::Attack` nem safelist de localhost
 * no caminho — a cicatriz que proíbe validar por `127.0.0.1` é sobre requisição que
 * passa pelo Rails.
 */
// Bloco 0.11 — o fixture anti-erro (ver `spec/e2e/fixtures.js`). Import DAQUI, nunca de
// `@playwright/test`: e a regra MUST do §10.3 do PLANO-MESTRE.
const { test, expect } = require('../../fixtures');

const TITULO_COM_EMOJI = '🔥 Política de trocas e devoluções';
const TITULO_SEM_EMOJI = 'Política de trocas e devoluções';
const TITULO_INTERNO = 'Manual interno de atendimento';
// WCAG 2.1 AA para texto pequeno. A citação é 0.6875rem (11 px) e peso normal, então é
// texto pequeno sem discussão — 3:1 (texto grande) não se aplica aqui.
const AA_TEXTO_PEQUENO = 4.5;

/** Relative luminance da WCAG 2.1, sobre canais 0–255. */
const luminancia = ([r, g, b]) => {
  const [rl, gl, bl] = [r, g, b]
    .map(c => c / 255)
    .map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
};

const contraste = (a, b) => {
  const [claro, escuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (escuro + 0.05);
};

const canais = cor => (cor.match(/[\d.]+/g) || []).map(Number).slice(0, 3);

let servidor;
let medidas = [];

test.beforeAll(async () => {
  const { iniciar } = await import('./harness.mjs');
  servidor = await iniciar();
});

test.afterAll(async () => {
  if (servidor) await servidor.encerrar();
  // A saída vai para o relatório do bloco: número medido, não adjetivo.
  // eslint-disable-next-line no-console
  console.log('\nMEDIDO NO CHROMIUM:\n' + medidas.join('\n'));
});

const abrir = async (page, { escuro }) => {
  await page.goto(servidor.url, { waitUntil: 'domcontentloaded' });
  if (escuro) {
    await page.evaluate(() => document.documentElement.classList.add('dark'));
  }
  await expect(page.locator('.citation-list')).toBeVisible();
};

/**
 * O fundo EFETIVO atrás de um elemento: sobe pelos ancestrais até o primeiro que não
 * seja transparente. Ler `background-color` do próprio rodapé devolveria
 * `rgba(0, 0, 0, 0)` — ele não pinta fundo nenhum, quem pinta é a conversa.
 */
const fundoEfetivo = seletor =>
  `(() => {
    let no = document.querySelector('${seletor}');
    while (no) {
      const cor = getComputedStyle(no).backgroundColor;
      const alfa = (cor.match(/[\\d.]+/g) || [])[3];
      if (cor && cor !== 'transparent' && alfa !== '0') return cor;
      no = no.parentElement;
    }
    return 'rgb(255, 255, 255)';
  })()`;

// `forEach` e não `for...of`: o `no-restricted-syntax` do projeto barra o segundo.
[
  { nome: 'claro', escuro: false },
  { nome: 'escuro', escuro: true },
].forEach(tema => {
  test.describe(`tema ${tema.nome}`, () => {
    test('a cor da citação resolveu e tem contraste AA sobre o fundo da conversa', async ({
      page,
    }) => {
      await abrir(page, tema);

      const rotulo = page.locator('.citation-list__label');
      const corTexto = await rotulo.evaluate(el => getComputedStyle(el).color);
      const corFundo = await page.evaluate(fundoEfetivo('.citation-list'));

      // GUARDA CONTRA O PRÓPRIO ERRO: preto puro aqui não é uma cor escolhida, é o
      // sinal de que `--slate-11` não resolveu e a medição está medindo o herdado.
      expect(corTexto).not.toBe('rgb(0, 0, 0)');
      // E o fundo tem de ser o da conversa, não o branco de fallback da função acima.
      expect(corFundo).not.toBe('rgba(0, 0, 0, 0)');

      const razao = contraste(canais(corTexto), canais(corFundo));
      medidas.push(
        `  [${tema.nome}] citação ${corTexto} sobre ${corFundo} = ${razao.toFixed(2)}:1`
      );
      expect(razao).toBeGreaterThanOrEqual(AA_TEXTO_PEQUENO);
    });

    test('o link da fonte é distinguível sem depender da cor', async ({
      page,
    }) => {
      await abrir(page, tema);

      const link = page.locator('.citation-list__link');
      const decoracao = await link.evaluate(
        el => getComputedStyle(el).textDecorationLine
      );
      // Cor não pode ser o único sinal de "isto é clicável" (WCAG 1.4.1). O sublinhado
      // é o que sobra para quem não distingue as duas cores.
      expect(decoracao).toBe('underline');
    });

    test('o nome acessível do link não carrega o emoji do título', async ({
      page,
    }) => {
      await abrir(page, tema);

      // A árvore de acessibilidade do PRÓPRIO Chromium, lida por CDP — é ela que o
      // leitor de tela consome. Não se usa `getByRole({ name })` aqui de propósito:
      // aquele matcher calcula o nome com a implementação do Playwright, e o que este
      // teste precisa provar é o que o NAVEGADOR computou. (`page.accessibility` foi
      // removida na 1.59; CDP é o caminho que restou para a árvore de verdade.)
      const cdp = await page.context().newCDPSession(page);
      await cdp.send('Accessibility.enable');
      const { nodes } = await cdp.send('Accessibility.getFullAXTree');
      const links = nodes
        .filter(no => no.role?.value === 'link' && !no.ignored)
        .map(no => ({ name: no.name?.value ?? '' }));

      expect(links.length).toBe(1);
      expect(links[0].name).toBe(`Abrir o documento ${TITULO_SEM_EMOJI}`);
      // A regra inteira do eixo: o símbolo SOME do nome e FICA na tela.
      expect(links[0].name).not.toContain('🔥');
      medidas.push(`  [${tema.nome}] nome acessível = "${links[0].name}"`);

      const visivel = await page.locator('.citation-list__link').innerText();
      expect(visivel).toBe(TITULO_COM_EMOJI);
    });

    test('a fonte sem URL pública não vira link', async ({ page }) => {
      await abrir(page, tema);

      const semLink = page.locator('.citation-list__text');
      await expect(semLink).toHaveText(TITULO_INTERNO);
      // Um link que não abre é pior que nenhum link: o aceite é que ele não exista.
      expect(await page.locator('.citation-list a').count()).toBe(1);
    });

    test('o rodapé não transborda a largura da conversa', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 700 });
      await abrir(page, tema);

      // `scrollWidth` NÃO serve aqui: em elemento com `overflow: visible` ele devolve a
      // largura da CAIXA, e o teste nunca falharia. Compara-se caixa com caixa.
      const transbordo = await page.evaluate(() => {
        const lista = document.querySelector('.citation-list');
        const conversa = document.querySelector('.conversation-wrap');
        const a = lista.getBoundingClientRect();
        const b = conversa.getBoundingClientRect();
        return Math.round(Math.max(0, a.right - b.right, b.left - a.left));
      });
      medidas.push(`  [${tema.nome}] transbordo em 375 px = ${transbordo} px`);
      expect(transbordo).toBe(0);
    });
  });
});
