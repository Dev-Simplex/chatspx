const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

/**
 * A tela de gatilhos num NAVEGADOR de verdade (bloco 4.04).
 *
 * O que so aqui e verificavel: se o cartao "pre-selecionado" esta MESMO
 * destacado (o jsdom nao computa outline), se o dialogo do nivel Agressivo
 * abre de fato, e se os avisos aparecem legiveis nos dois temas do painel.
 */

const abrir = async (page, { theme = 'light', stored = '' } = {}) => {
  const erros = [];
  page.on('console', msg => {
    if (msg.type() === 'error') erros.push(msg.text());
  });
  page.on('pageerror', erro => erros.push(erro.message));

  await page.goto(`/triggers?theme=${theme}${stored ? '&stored=1' : ''}`);
  await page.waitForSelector('[data-testid="approach-bold"]');
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
      expect(texto).toContain('Abordagem');
      expect(texto).toContain('Tempo na página');
    });

    test('Chamativo é o único destacado — e o destaque é visível, não só o atributo', async ({
      page,
    }) => {
      await abrir(page, { theme });

      const marcados = await page.evaluate(() =>
        ['discreet', 'bold', 'aggressive'].map(nivel => ({
          nivel,
          checked: document.querySelector(
            `[data-testid="approach-${nivel}"] input`
          ).checked,
          outline: getComputedStyle(
            document.querySelector(`[data-testid="approach-${nivel}"]`)
          ).outlineColor,
        }))
      );

      expect(marcados.map(m => m.checked)).toEqual([false, true, false]);
      // o cartão ativo tem outline DIFERENTE dos outros dois — é o que o
      // administrador enxerga; `checked` sozinho passaria com os três iguais
      const [discreet, bold, aggressive] = marcados;
      expect(bold.outline).not.toBe(discreet.outline);
      expect(discreet.outline).toBe(aggressive.outline);
    });

    test('o aviso do gatilho composto aparece ao ligar só tempo, e é legível', async ({
      page,
    }) => {
      await abrir(page, { theme });
      await expect(
        page.locator('[data-testid="composite-warning"]')
      ).toHaveCount(0);

      await page.click('[data-testid="desktop-time_on_page"]');

      const aviso = page.locator('[data-testid="composite-warning"]');
      await expect(aviso).toBeVisible();
      await expect(aviso).toContainText('saiu para pegar um café');

      // mede o no que TEM o texto, e o fundo do ancestral que o pinta: medir o
      // container do Banner devolveria a cor que ele define para si, nao a que
      // o administrador le
      const cores = await aviso.evaluate(el => {
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
      });
      expect(contraste(rgb(cores.texto), rgb(cores.fundo))).toBeGreaterThan(
        4.5
      );
    });

    test('axe-core não acusa violação crítica ou séria', async ({ page }) => {
      await abrir(page, { theme });

      const { violations } = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze();

      const graves = violations
        .filter(v => ['critical', 'serious'].includes(v.impact))
        .flatMap(v => v.nodes.map(no => `${v.id} @ ${no.target.join(' ')}`));

      expect(graves).toEqual([]);
    });
  });
});

test.describe('o nível Agressivo', () => {
  test('abre o aviso de verdade, e o aviso nomeia o nível do celular', async ({
    page,
  }) => {
    await abrir(page);

    await page.click('[data-testid="approach-aggressive"] input');

    const dialogo = page.locator('dialog[open]');
    await expect(dialogo).toBeVisible();
    await expect(dialogo).toContainText('Abrir o painel sozinho?');
    await expect(
      page.locator('[data-testid="auto-open-points"]')
    ).toContainText('Chamativo');
  });

  test('cancelar deixa o rascunho intacto — nada pendente para salvar', async ({
    page,
  }) => {
    await abrir(page);
    await page.click('[data-testid="approach-aggressive"] input');
    await page.locator('dialog[open] button[type="button"]').first().click();

    await expect(page.locator('dialog[open]')).toHaveCount(0);
    await expect(page.locator('[data-testid="pending-count"]')).toHaveCount(0);
  });

  test('confirmar liga o nível e a barra anuncia o que mudou', async ({
    page,
  }) => {
    await abrir(page);
    await page.click('[data-testid="approach-aggressive"] input');
    await page.locator('dialog[open] button[type="submit"]').click();

    await expect(
      page.locator('[data-testid="approach-mobile-note"]')
    ).toContainText('Chamativo');
    await expect(page.locator('[data-testid="pending-count"]')).toBeVisible();
  });
});

test.describe('o que já está gravado', () => {
  test('a tela mostra o que veio do banco, não os defaults', async ({
    page,
  }) => {
    await abrir(page, { stored: true });

    expect(
      await page.locator('[data-testid="approach-discreet"] input').isChecked()
    ).toBe(true);
    expect(
      await page
        .locator('[data-testid="desktop-value-time_on_page"] input')
        .inputValue()
    ).toBe('12');
    await expect(
      page.locator('[data-testid="degrade-off-warning"]')
    ).toBeVisible();
    // e nada está pendente: mostrar o gravado não é editar
    await expect(page.locator('[data-testid="pending-count"]')).toHaveCount(0);
  });

  test('o seletor CSS inválido reclama no blur, com a razão do parser', async ({
    page,
  }) => {
    await abrir(page);
    // `input[...]`: o componente Input repassa os atributos ao campo E deixa o
    // fallthrough do Vue coloca-los tambem na div raiz — dois nos com o mesmo
    // data-testid, e o locator sem tag reclama de ambiguidade
    const campo = page.locator(
      'input[data-testid="selector-input-element_click"]'
    );

    await campo.fill('#$%(((');
    await expect(
      page.locator('[data-testid="selector-field-element_click"]')
    ).toContainText('Conferimos só a escrita');

    await campo.blur();

    await expect(
      page.locator('[data-testid="selector-field-element_click"]')
    ).toContainText('Este seletor não é válido');
  });
});
