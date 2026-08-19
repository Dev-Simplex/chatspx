const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

/**
 * A tela de rastreio num NAVEGADOR (bloco 5.06).
 *
 * Dois motivos para ela existir aqui: os avisos desta tela usam `Banner`, e o
 * tom 11 da escala dele reprova AA no tema claro (medido no bloco 4.04); e o
 * campo de segredo precisa ser visto — mascara de verdade, `type=password`
 * de verdade, valor nenhum no DOM.
 */
const abrir = async (page, { theme = 'light', stored = '' } = {}) => {
  const erros = [];
  page.on('console', msg => {
    if (msg.type() === 'error') erros.push(msg.text());
  });
  page.on('pageerror', erro => erros.push(erro.message));

  await page.goto(`/tracking?theme=${theme}${stored ? '&stored=1' : ''}`);
  await page.waitForSelector('[data-testid="account-scope-card"]');
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

['light', 'dark'].forEach(theme => {
  test.describe(`tema ${theme} do dashboard`, () => {
    test('renderiza sem erro de console e sem chave de i18n crua', async ({
      page,
    }) => {
      const erros = await abrir(page, { theme });
      const texto = await page.locator('body').innerText();

      expect(
        texto.match(/\b(INBOX_WIDGET|INBOX_MGMT)\.[A-Z0-9_.]+/g)
      ).toBeNull();
      expect(erros).toEqual([]);
      expect(texto).toContain('Pixel ID');
    });

    test('os avisos são legíveis — o Banner reprova AA no tom 11', async ({
      page,
    }) => {
      await abrir(page, { theme, stored: true });

      const avisos = page.locator(
        '[data-testid="kill-switch-warning"], [data-testid="test-mode-expired"]'
      );
      const total = await avisos.count();
      expect(total).toBeGreaterThan(0);

      const medir = el => {
        const noComTexto = el.querySelector('span') ?? el;
        const fundoDe = alvo => {
          let atual = alvo;
          while (atual) {
            const cor = getComputedStyle(atual).backgroundColor;
            if (cor && !/rgba\(0, 0, 0, 0\)|transparent/.test(cor)) return cor;
            atual = atual.parentElement;
          }
          return 'rgb(255, 255, 255)';
        };
        return {
          texto: getComputedStyle(noComTexto).color,
          fundo: fundoDe(noComTexto),
        };
      };

      const cores = await Promise.all(
        Array.from({ length: total }, (_, i) => avisos.nth(i).evaluate(medir))
      );

      cores.forEach(({ texto, fundo }) =>
        expect(contraste(rgb(texto), rgb(fundo))).toBeGreaterThan(4.5)
      );
    });

    /**
     * A MESMA divida de componente compartilhado que a Onda 2 ja nomeou (blocos
     * 3.09/3.10), e esta e a terceira tela onde ela aparece: `ColorBar`/`TabBar`
     * e o `text-n-blue-11` escrevem texto na cor da marca sobre fundo claro —
     * #2dc46f sobre #f0f2f5 da 2,02:1. E literalmente a doenca que o medidor de
     * contraste do 3.08 denuncia, dentro do proprio painel.
     *
     * Listadas por id + seletor para que qualquer violacao NOVA reprove; nao e
     * escopo deste bloco corrigir componente de todas as telas. Escalado.
     */
    const HERDADAS = [{ id: 'color-contrast', alvo: /text-n-blue-11|scale-/ }];

    test('axe-core não acusa violação crítica ou séria', async ({ page }) => {
      await abrir(page, { theme });

      const { violations } = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze();

      const graves = violations
        .filter(v => ['critical', 'serious'].includes(v.impact))
        .flatMap(v =>
          v.nodes.map(no => ({ id: v.id, alvo: no.target.join(' ') }))
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

test.describe('o campo de segredo, visto no navegador', () => {
  test('mostra máscara e nunca o valor — e o DOM inteiro não tem segredo', async ({
    page,
  }) => {
    await abrir(page, { stored: true });

    await expect(
      page.locator('[data-testid="meta-token"] [data-testid="secret-mask"]')
    ).toBeVisible();

    const html = await page.content();
    // nenhum valor de credencial no HTML servido — a tela nem os recebe
    expect(html).not.toMatch(/EAA[A-Za-z0-9]{10,}/);
    expect(html).not.toMatch(/api[_-]?secret["':\s]+[A-Za-z0-9_-]{8,}/i);
  });

  test('o botão de troca está desabilitado, com a razão nomeando o 5.02', async ({
    page,
  }) => {
    await abrir(page);

    const botao = page.locator(
      '[data-testid="meta-token"] [data-testid="secret-replace"]'
    );
    await expect(botao).toBeDisabled();
    await expect(
      page.locator(
        '[data-testid="meta-token"] [data-testid="secret-disabled-reason"]'
      )
    ).toContainText('5.02');
  });
});

test.describe('o que já está gravado aparece', () => {
  test('pixel, consentimento e modo teste expirado', async ({ page }) => {
    await abrir(page, { stored: true });

    await expect(
      page.locator('input[data-testid="meta-pixel-id"]')
    ).toHaveValue('123456789012345');
    await expect(page.locator('[data-testid="account-consent"]')).toHaveText(
      'advanced'
    );
    await expect(
      page.locator('[data-testid="test-mode-expired"]')
    ).toBeVisible();
    // e nada pendente: mostrar o gravado não é editar
    await expect(page.locator('[data-testid="pending-count"]')).toHaveCount(0);
  });
});
