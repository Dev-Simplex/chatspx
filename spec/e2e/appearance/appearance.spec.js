// Bloco 0.11 — fixture anti-erro. Import DAQUI, nunca de `@playwright/test`.
const { test, expect } = require('../fixtures');
const AxeBuilder = require('@axe-core/playwright').default;

/**
 * A tela de aparência num NAVEGADOR de verdade.
 *
 * O que só aqui é verificável: o CSS. O jsdom não computa cor, não aplica
 * `@layer`, não resolve custom property — e é exatamente aí que moram os dois
 * defeitos que esta onda conserta (o preview que copiava a paleta do widget, e
 * o tema do preview que era o tema do painel).
 */

const abrir = async (page, { theme = 'light', locale = 'pt_BR' } = {}) => {
  const erros = [];
  page.on('console', msg => {
    if (msg.type() === 'error') erros.push(msg.text());
  });
  page.on('pageerror', erro => erros.push(erro.message));

  await page.goto(`/appearance?theme=${theme}&locale=${locale}`);
  await page.waitForSelector('[data-testid="contrast-readout"]');
  return erros;
};

const luminancia = ([r, g, b]) => {
  const canal = v => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
};

const contraste = (a, b) => {
  const [claro, escuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (escuro + 0.05);
};

const rgb = texto => texto.match(/\d+/g).slice(0, 3).map(Number);

// Um bloco por tema do dashboard: as duas superfícies são caminhos de CSS
// diferentes, e foi no escuro que o defeito apareceu.
['light', 'dark'].forEach(theme => {
  test.describe(`tema ${theme} do dashboard`, () => {
    test('renderiza sem erro de console e sem chave de i18n crua', async ({
      page,
    }) => {
      const erros = await abrir(page, { theme });

      const texto = await page.locator('body').innerText();
      const cruas = texto.match(/\b(INBOX_WIDGET|INBOX_MGMT)\.[A-Z0-9_.]+/g);

      expect(cruas).toBeNull();
      expect(erros).toEqual([]);
      expect(texto).toContain('Cor da marca');
      expect(texto).toContain('Lançador');
    });

    test('o medidor exibe 2,27:1 para o verde da marca e diz que ajustou', async ({
      page,
    }) => {
      await abrir(page, { theme });
      const linha = page.locator('[data-testid="contrast-brandAsTextLight"]');

      await expect(linha.locator('[data-testid="ratio"]')).toHaveText('2,27:1');
      await expect(
        linha.locator('[data-testid="verdict-adjusted"]')
      ).toHaveText('ajustamos');
    });

    test('nenhum texto da tela fica abaixo de 4,5:1 contra o próprio fundo', async ({
      page,
    }) => {
      await abrir(page, { theme });

      const reprovados = await page.evaluate(() => {
        const fundoDe = el => {
          let atual = el;
          while (atual) {
            const cor = getComputedStyle(atual).backgroundColor;
            if (cor && !/rgba\(0, 0, 0, 0\)|transparent/.test(cor)) return cor;
            atual = atual.parentElement;
          }
          return 'rgb(255, 255, 255)';
        };
        // Só quem tem texto PRÓPRIO. Um `<li>` cujo texto mora todo em spans
        // filhos com cor própria não é um caso de contraste — medi-lo dava 89
        // falsos positivos, todos eles o contêiner de um texto que estava
        // legível dentro.
        const temTextoProprio = el =>
          [...el.childNodes].some(
            no => no.nodeType === Node.TEXT_NODE && no.textContent.trim()
          );

        return [
          ...document.querySelectorAll('p, span, h3, h4, label, li, a, button'),
        ]
          .filter(
            el =>
              temTextoProprio(el) &&
              el.innerText?.trim() &&
              el.offsetParent !== null
          )
          .map(el => ({
            texto: el.innerText.trim().slice(0, 40),
            cor: getComputedStyle(el).color,
            fundo: fundoDe(el),
          }));
      });

      const abaixo = reprovados
        .map(item => ({
          ...item,
          razao: contraste(rgb(item.cor), rgb(item.fundo)),
        }))
        .filter(item => item.razao < 4.5);

      expect(abaixo).toEqual([]);
    });

    /**
     * Três violações não nascem nesta tela — nascem em componentes do
     * dashboard que ela usa, e corrigi-las aqui seria remendo local num
     * problema de todo o painel. Estão NOMEADAS uma a uma, com o seletor, para
     * que qualquer violação nova (ou uma destas em outro lugar) reprove:
     *
     *  1. `ColorPicker` — o hex é escrito em `text-n-blue-11`, que no fork vale
     *     o verde da marca: #2dc46f sobre #f0f2f5 dá **2,02:1**. É literalmente
     *     a doença que o medidor desta tela denuncia, dentro do próprio painel.
     *  2. `TabBar` — a aba ativa usa a mesma cor de marca como texto: 2,09:1.
     *  3. `Avatar` — `role="img"` sem nome acessível quando renderiza inicial.
     *     (Aqui a tela já o marcou `aria-hidden`; a exceção cobre o caso de o
     *     componente aparecer por outro caminho.)
     *
     * Escalado ao coordenador; não é escopo do bloco 3.09/3.10 mexer neles.
     */
    const HERDADAS = [
      { id: 'color-contrast', alvo: /text-n-blue-11|scale-/ },
      { id: 'role-img-alt', alvo: /object-cover/ },
    ];

    test('axe-core não acusa violação crítica ou séria', async ({ page }) => {
      await abrir(page, { theme });

      const { violations } = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze();

      const graves = violations
        .filter(v => ['critical', 'serious'].includes(v.impact))
        .flatMap(v =>
          v.nodes.map(node => ({ id: v.id, alvo: node.target.join(' ') }))
        )
        .filter(
          item =>
            !HERDADAS.some(
              herdada => herdada.id === item.id && herdada.alvo.test(item.alvo)
            )
        );

      expect(graves).toEqual([]);
    });
  });
});

test.describe('o preview tem tema próprio', () => {
  const fundoDoPainel = page =>
    page
      .locator('.widget-wrapper')
      .evaluate(el => getComputedStyle(el).backgroundColor);

  test('com o dashboard CLARO, ligar o toggle escurece só o preview', async ({
    page,
  }) => {
    await abrir(page, { theme: 'light' });

    const claro = await fundoDoPainel(page);
    await page.locator('[data-testid="preview-theme-toggle"]').click();
    const escuro = await fundoDoPainel(page);

    expect(claro).not.toBe(escuro);
    // o painel do widget no claro é branco; no escuro, o `--solid-1` do widget
    expect(rgb(claro)).toEqual([255, 255, 255]);
    expect(rgb(escuro)).toEqual([23, 23, 26]);
    // e o dashboard em volta NÃO foi repintado: o `:root` continua com a
    // paleta do painel, que é o que o `:root` do preview destruiria
    const rootSolid1 = await page.evaluate(() =>
      getComputedStyle(document.documentElement)
        .getPropertyValue('--solid-1')
        .trim()
    );
    expect(rootSolid1).not.toBe('23 23 26');
  });

  test('com o dashboard ESCURO, o preview começa claro — não herda o painel', async ({
    page,
  }) => {
    await abrir(page, { theme: 'dark' });

    expect(rgb(await fundoDoPainel(page))).toEqual([255, 255, 255]);
  });

  test('o balão do visitante usa a cor da marca com texto legível', async ({
    page,
  }) => {
    await abrir(page, { theme: 'light' });
    await page.locator('[data-testid="preview-chat-toggle"]').click();

    const balao = page.locator('.bg-w-brand').first();
    const cores = await balao.evaluate(el => ({
      fundo: getComputedStyle(el).backgroundColor,
      texto: getComputedStyle(el).color,
    }));

    expect(rgb(cores.fundo)).toEqual([45, 196, 111]);
    // o defeito que esta onda conserta: texto BRANCO aqui daria 2,27:1
    expect(rgb(cores.texto)).toEqual([0, 0, 0]);
    expect(contraste(rgb(cores.fundo), rgb(cores.texto))).toBeGreaterThan(4.5);
  });
});
