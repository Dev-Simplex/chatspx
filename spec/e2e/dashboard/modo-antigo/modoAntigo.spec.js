/**
 * Aceite de APARÊNCIA e de NOME ACESSÍVEL da seção "modo antigo" — bloco 4.22.
 *
 * Os 10 testes de unidade provam a LÓGICA (quem entra na lista, qual aviso, o que o
 * botão chama). Eles rodam em jsdom, que não resolve cascata nem custom property: ele
 * confirma que a classe está lá, nunca que a cor chegou. Aqui se mede no Chromium:
 *
 *   1. o AVISO é legível nos dois temas. Ele é o produto desta seção — se o cliente não
 *      o ler, vai procurar o defeito no lugar errado quando a campanha parar de
 *      aparecer no site dele. Um aviso ilegível é pior que nenhum, porque ocupa o
 *      espaço de um que funcionaria;
 *   2. o NOME ACESSÍVEL do botão vem da árvore do próprio navegador, sem o emoji do
 *      título que o cliente escreveu.
 */
const { test, expect } = require('@playwright/test');

const AA_TEXTO_PEQUENO = 4.5;

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

/** O fundo EFETIVO: sobe pelos ancestrais até o primeiro que não seja transparente. */
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

let servidor;
const medidas = [];

test.beforeAll(async () => {
  const { iniciar } = await import('./harness.mjs');
  servidor = await iniciar();
});

test.afterAll(async () => {
  if (servidor) await servidor.encerrar();
  // eslint-disable-next-line no-console
  console.log('\nMEDIDO NO CHROMIUM:\n' + medidas.join('\n'));
});

const abrir = async (page, { escuro }) => {
  await page.goto(servidor.url, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('[data-testid="modo-antigo"]')).toBeVisible();
  if (escuro) {
    await page.evaluate(() => window.alternarTema(true));
  }
};

[
  { nome: 'claro', escuro: false },
  { nome: 'escuro', escuro: true },
].forEach(tema => {
  test.describe(`tema ${tema.nome}`, () => {
    test('o aviso do modo antigo é legível — ele é o produto da seção', async ({
      page,
    }) => {
      await abrir(page, tema);

      const aviso = page.locator('[data-testid="modo-antigo-aviso"]');
      await expect(aviso).toBeVisible();

      // Mede o nó que de fato carrega o texto, não o contêiner: o Banner desenha o
      // texto num filho, e ler a cor do contêiner mediria a cor herdada.
      const corTexto = await aviso.evaluate(el => {
        const alvo =
          [...el.querySelectorAll('*')].find(
            filho => filho.textContent.trim().length > 20
          ) || el;
        return getComputedStyle(alvo).color;
      });
      const corFundo = await page.evaluate(
        fundoEfetivo('[data-testid="modo-antigo-aviso"]')
      );

      // GUARDA CONTRA O PRÓPRIO ERRO: preto puro aqui é sinal de token não resolvido.
      expect(corTexto).not.toBe('rgb(0, 0, 0)');

      const razao = contraste(canais(corTexto), canais(corFundo));
      medidas.push(
        `  [${tema.nome}] aviso ${corTexto} sobre ${corFundo} = ${razao.toFixed(2)}:1`
      );
      expect(razao).toBeGreaterThanOrEqual(AA_TEXTO_PEQUENO);
    });

    test('o nome acessível do botão diz QUAL campanha, e sem o emoji do título', async ({
      page,
    }) => {
      await abrir(page, tema);

      // Árvore de acessibilidade do próprio Chromium, por CDP — é ela que o leitor de
      // tela consome. `getByRole({ name })` calcularia o nome com a implementação do
      // Playwright, e o que se prova aqui é o que o NAVEGADOR computou.
      const cdp = await page.context().newCDPSession(page);
      await cdp.send('Accessibility.enable');
      const { nodes } = await cdp.send('Accessibility.getFullAXTree');
      const botoes = nodes
        .filter(no => no.role?.value === 'button' && !no.ignored)
        .map(no => no.name?.value ?? '')
        .filter(nome => nome.includes('Importar'));

      expect(botoes.length).toBe(1);
      expect(botoes[0]).toBe(
        'Importar a campanha Convite dos planos como gatilho'
      );
      expect(botoes[0]).not.toContain('🔥');
      medidas.push(`  [${tema.nome}] nome acessível = "${botoes[0]}"`);

      // E o símbolo continua na TELA — a regra inteira do eixo.
      await expect(page.locator('[data-testid="modo-antigo"]')).toContainText(
        '🔥'
      );
    });

    test('a seção não transborda a largura da página', async ({ page }) => {
      await page.setViewportSize({ width: 900, height: 700 });
      await abrir(page, tema);

      // `getBoundingClientRect` e nunca `scrollWidth`: em elemento com overflow
      // visible o scrollWidth devolve a largura da CAIXA e o teste jamais falharia.
      const transbordo = await page.evaluate(() => {
        const secao = document.querySelector('[data-testid="modo-antigo"]');
        const pai = secao.parentElement;
        const a = secao.getBoundingClientRect();
        const b = pai.getBoundingClientRect();
        return Math.round(Math.max(0, a.right - b.right, b.left - a.left));
      });
      medidas.push(`  [${tema.nome}] transbordo em 900 px = ${transbordo} px`);
      expect(transbordo).toBe(0);
    });
  });
});
