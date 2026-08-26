/* eslint-disable no-restricted-syntax, no-await-in-loop --
   Aqui o laco e sequencial de proposito: cada iteracao navega a MESMA `page`,
   entao paralelizar nao e uma escolha de estilo, e impossivel. */
const { test, expect } = require('@playwright/test');

/**
 * Tela de configuracao da caixa de entrada — o que este arquivo mede.
 *
 * Os cinco defeitos aqui foram medidos em Chromium contra a instalacao de
 * homologacao (conta 3, caixa 6) antes de existir conserto. Este arquivo repete
 * as MESMAS medicoes contra o codigo do repositorio, montando a `Settings.vue`
 * de verdade num harness (`harness/entry.js`) com a largura fiel: na instalacao
 * a tela nao recebe o viewport inteiro, ela recebe os 960 px que
 * `Wrapper.vue:33` impoe ao `<router-view>` — e e por isso que a barra de abas
 * mede 912 px tanto em 1280 quanto em 1440.
 *
 * O numero medido na instalacao, antes do conserto, esta ao lado de cada
 * asserção. Nenhum teste aqui olha "existe o elemento": todos leem geometria
 * ou cor, que e o unico jeito de o verde significar alguma coisa. Build verde e
 * HTTP 200 ja enganaram esta base.
 */

const VIEWPORTS = [
  { width: 1280, height: 900 },
  { width: 1440, height: 900 },
];

const THEMES = ['light', 'dark'];

const open = async (
  page,
  { theme = 'light', tab = null, locale = null } = {}
) => {
  const query = new URLSearchParams({ theme });
  if (tab) query.set('tab', tab);
  if (locale) query.set('locale', locale);
  await page.goto(`/inbox-config?${query.toString()}`, {
    waitUntil: 'networkidle',
  });
  await page.waitForSelector('ul[role="tablist"] li', { timeout: 30000 });
  // O `computeOverflow` do Tabs.vue roda em `onMounted` + ResizeObserver; sem
  // ceder um frame o chevron ainda nao decidiu se aparece.
  await page.waitForTimeout(600);
};

/**
 * Razao de contraste WCAG 2.x, calculada no navegador a partir do
 * `getComputedStyle`.
 *
 * O detalhe que faz a medicao valer: fundo com ALFA precisa ser composto. A
 * primeira versao deste helper parava no primeiro `background-color` diferente
 * de transparente e tratava `rgba(0, 168, 132, 0.14)` como se fosse opaco —
 * devolvia 1,33:1 para um rotulo que na tela tem contraste bem maior. Numero
 * errado reprova codigo bom, que e o pior tipo de teste.
 */
const CONTRAST_HELPERS = `
  const _lin = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
  const _parse = s => {
    const m = (String(s).match(/[\\d.]+/g) || []).map(Number);
    return { r: m[0] || 0, g: m[1] || 0, b: m[2] || 0, a: m.length > 3 ? m[3] : 1 };
  };
  const _over = (f, b) => ({
    r: f.r * f.a + b.r * (1 - f.a),
    g: f.g * f.a + b.g * (1 - f.a),
    b: f.b * f.a + b.b * (1 - f.a),
    a: 1,
  });
  const _bgOf = el => {
    let node = el;
    let acc = null;
    while (node) {
      const c = _parse(getComputedStyle(node).backgroundColor);
      if (c.a > 0) {
        acc = acc ? _over(acc, c) : c;
        if (c.a >= 1) return { ...acc, a: 1 };
      }
      node = node.parentElement;
    }
    // Sem nenhuma camada opaca ate a raiz, o navegador pinta branco.
    return acc ? _over(acc, { r: 255, g: 255, b: 255, a: 1 }) : { r: 255, g: 255, b: 255, a: 1 };
  };
  const _lum = c => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
  const _ratio = (fgString, el) => {
    const bg = _bgOf(el);
    const raw = _parse(fgString);
    const fg = raw.a < 1 ? _over(raw, bg) : raw;
    const a = _lum(fg);
    const b = _lum(bg);
    const [hi, lo] = a > b ? [a, b] : [b, a];
    return (hi + 0.05) / (lo + 0.05);
  };
`;

// ---------------------------------------------------------------------------
// 1. As abas
// ---------------------------------------------------------------------------

test.describe('1. barra de abas', () => {
  test('nenhuma aba repete o nome de outra', async ({ page }) => {
    await open(page);
    const names = await page.$$eval('ul[role="tablist"] li', items =>
      items.map(item => item.innerText.trim())
    );

    // Medido antes: "Configurações" (dados da caixa), "Configuração" (o
    // snippet de instalacao) e "Configuração do Bot" conviviam na mesma barra,
    // e as duas ultimas estavam fora da vista. Tres nomes que dizem a mesma
    // coisa e nenhum diz o que a aba faz.
    expect(names).toContain('Geral');
    expect(names).toContain('Instalação');
    expect(names).toContain('Bot');
    expect(names).not.toContain('Configurações');
    expect(names).not.toContain('Configuração');
    expect(names).not.toContain('Configuração do Bot');

    // Nenhum nome pode ser prefixo de outro: e o que fazia "Configuração" e
    // "Configurações" serem indistinguiveis com a barra cortada.
    const collisions = names.filter(a =>
      names.some(b => b !== a && b.startsWith(a))
    );
    expect(collisions, `nomes ambiguos: ${collisions.join(', ')}`).toEqual([]);
  });

  test('em ingles os tres nomes tambem sao distintos', async ({ page }) => {
    await open(page, { locale: 'en' });
    const names = await page.$$eval('ul[role="tablist"] li', items =>
      items.map(item => item.innerText.trim())
    );
    expect(names).toContain('General');
    expect(names).toContain('Installation');
    expect(names).toContain('Bot');
    expect(names).not.toContain('Configuration');
    expect(names).not.toContain('Bot Configuration');
  });

  for (const viewport of VIEWPORTS) {
    for (const theme of THEMES) {
      test(`nenhuma aba fica fora da vista em ${viewport.width} (${theme})`, async ({
        page,
      }) => {
        await page.setViewportSize(viewport);
        await open(page, { theme });

        const measured = await page.evaluate(() => {
          const list = document.querySelector('ul[role="tablist"]');
          const box = list.getBoundingClientRect();
          return {
            scrollWidth: list.scrollWidth,
            clientWidth: list.clientWidth,
            fora: [...list.querySelectorAll('li')]
              .filter(item => {
                const rect = item.getBoundingClientRect();
                return rect.left < box.left - 1 || rect.right > box.right + 1;
              })
              .map(item => item.innerText.trim()),
          };
        });

        // Medido na instalacao antes do conserto, nas duas larguras:
        // scrollWidth 1154 x clientWidth 912 — 242 px de transbordo, com
        // "Configuração" e "Configuração do Bot" inalcancaveis.
        expect(
          measured.scrollWidth,
          `transborda ${measured.scrollWidth - measured.clientWidth} px`
        ).toBeLessThanOrEqual(measured.clientWidth + 2);
        expect(measured.fora).toEqual([]);
      });
    }
  }

  test('quando a barra transborda, o indicador de rolagem e visivel de verdade', async ({
    page,
  }) => {
    // Em 900 px o `max-w-[960px]` deixa de valer e a barra fica estreita: e a
    // condicao de transbordo REAL, sem CSS inventado pelo teste.
    await page.setViewportSize({ width: 900, height: 900 });
    await open(page);

    const measured = await page.evaluate(() => {
      const list = document.querySelector('ul[role="tablist"]');
      const chevron = document.querySelector('.wa-tabs-chevron-right');
      const icon = chevron?.querySelector('span');
      const iconRect = icon?.getBoundingClientRect();
      return {
        transborda: list.scrollWidth > list.clientWidth + 2,
        chevronVisivel: chevron
          ? getComputedStyle(chevron).display !== 'none'
          : false,
        iconeLargura: iconRect ? Math.round(iconRect.width) : 0,
        iconeAltura: iconRect ? Math.round(iconRect.height) : 0,
      };
    });

    expect(measured.transborda).toBe(true);
    expect(measured.chevronVisivel).toBe(true);
    // Medido na instalacao: o `<span i-lucide-chevron-right size-4>` pintava
    // 4 x 16 px — encolhia como flex-item dentro do `<button w-6 h-6>`. Uma
    // linha vertical de 4 px nao e affordance: some na captura de tela.
    expect(
      measured.iconeLargura,
      `o chevron pintou ${measured.iconeLargura}x${measured.iconeAltura} px`
    ).toBeGreaterThanOrEqual(14);

    // E ele tem de FUNCIONAR: apos rolar, a ultima aba entra na vista.
    const ultima = await page.evaluate(() => {
      const list = document.querySelector('ul[role="tablist"]');
      return [...list.querySelectorAll('li')].pop().innerText.trim();
    });
    // Um clique por vez, e so enquanto o botao ainda estiver visivel: assim que
    // o transbordo acaba o proprio Tabs.vue esconde o chevron, e insistir num
    // botao ja escondido faria o teste falhar por motivo errado.
    for (let i = 0; i < 6; i += 1) {
      const chevron = page.locator('.wa-tabs-chevron-right');
      if (!(await chevron.isVisible())) break;
      await chevron.click();
      await page.waitForTimeout(500);
    }
    const alcancou = await page.evaluate(() => {
      const list = document.querySelector('ul[role="tablist"]');
      const box = list.getBoundingClientRect();
      const item = [...list.querySelectorAll('li')].pop();
      const rect = item.getBoundingClientRect();
      return rect.left >= box.left - 1 && rect.right <= box.right + 1;
    });
    expect(alcancou, `"${ultima}" continua fora da vista apos rolar`).toBe(
      true
    );
  });
});

// ---------------------------------------------------------------------------
// 2. A foto do atendimento
// ---------------------------------------------------------------------------

test.describe('2. foto do atendimento', () => {
  test('a tela oferece avatares padrao e o upload da propria imagem', async ({
    page,
  }) => {
    await open(page);
    // Antes: um unico `input[type=file]` escondido atras de um circulo mudo.
    const opcoes = page.locator(
      '[data-testid="channel-avatar-gallery"] button'
    );
    await expect(opcoes).toHaveCount(8);
    await expect(
      page.locator('[data-testid="channel-avatar-upload"]')
    ).toBeVisible();
  });

  test('a tela diz o formato, o tamanho e onde a foto aparece', async ({
    page,
  }) => {
    await open(page);
    const specs = await page
      .locator('[data-testid="channel-avatar-specs"]')
      .innerText();
    expect(specs).toMatch(/PNG/i);
    expect(specs).toMatch(/JPG/i);
    expect(specs).toMatch(/250/);
    expect(specs).toMatch(/15\s*MB/i);

    const onde = await page
      .locator('[data-testid="channel-avatar-field"] p')
      .first()
      .innerText();
    expect(onde).toMatch(/cabeçalho/i);
    expect(onde).toMatch(/balão/i);
  });

  for (const theme of THEMES) {
    test(`escolher um avatar padrao aplica a foto no preview (${theme})`, async ({
      page,
    }) => {
      await open(page, { theme });

      // Estado inicial: sem foto, o balao do preview mostra a inicial "C"
      // cravada no `WidgetFooter` — que nunca foi a foto de ninguem.
      const antes = await page.evaluate(() => {
        const surface = document.querySelector(
          '[data-testid="widget-preview-surface"]'
        );
        return {
          temFoto: !!surface?.querySelector('img.logo, img[src*="atendente-"]'),
          iniciais: [...(surface?.querySelectorAll('span') ?? [])]
            .map(node => node.textContent.trim())
            .filter(text => text.length === 1),
        };
      });
      expect(antes.temFoto).toBe(false);

      await page.click('[data-testid="channel-avatar-option-atendente-3"]');
      await page.waitForTimeout(700);

      const depois = await page.evaluate(() => {
        const surface = document.querySelector(
          '[data-testid="widget-preview-surface"]'
        );
        const fotos = [...(surface?.querySelectorAll('img') ?? [])]
          .map(img => img.getAttribute('src') || '')
          .filter(src => src.includes('atendente-'));
        return {
          fotos,
          iniciais: [...(surface?.querySelectorAll('span') ?? [])]
            .map(node => node.textContent.trim())
            .filter(text => text.length === 1 && /^[A-Z]$/.test(text)),
          atual:
            document
              .querySelector('[data-testid="channel-avatar-current"] img')
              ?.getAttribute('src') || '',
        };
      });

      // O preview tem de mostrar a foto — no cabecalho E no balao — e parar de
      // mostrar a inicial. Sem as duas metades, o cliente ve uma coisa na tela
      // de configuracao e outra no site dele.
      expect(
        depois.fotos.length,
        'o preview nao aplicou a foto'
      ).toBeGreaterThanOrEqual(2);
      expect(depois.iniciais, 'o preview ainda mostra a inicial').toEqual([]);
      expect(depois.atual).toContain('atendente-3');
    });
  }
});

// ---------------------------------------------------------------------------
// 3. A barra do preview
// ---------------------------------------------------------------------------

test.describe('3. barra do preview', () => {
  for (const viewport of VIEWPORTS) {
    for (const theme of THEMES) {
      test(`nao transborda nem quebra rotulo em ${viewport.width} (${theme})`, async ({
        page,
      }) => {
        await page.setViewportSize(viewport);
        await open(page, { theme });

        const medido = await page.evaluate(() => {
          const toggle = document.querySelector(
            '[data-testid="preview-chat-toggle"]'
          );
          const bar = toggle.closest('div.flex.items-center.justify-between');
          const labels = [...bar.querySelectorAll('span')]
            .filter(node => node.children.length === 0 && node.innerText.trim())
            // Fora os `sr-only`: sao 1x1 px recortados, existem so para o
            // leitor de tela, e "cortado" neles nao quer dizer nada.
            .filter(node => {
              const rect = node.getBoundingClientRect();
              return rect.width > 4 && rect.height > 4;
            })
            .map(node => {
              const rect = node.getBoundingClientRect();
              const lineHeight =
                parseFloat(getComputedStyle(node).lineHeight) || 16;
              return {
                texto: node.innerText.trim(),
                linhas: Math.round(rect.height / lineHeight),
                cortado: node.scrollWidth > node.clientWidth + 1,
              };
            });
          return {
            scrollWidth: bar.scrollWidth,
            clientWidth: bar.clientWidth,
            labels,
          };
        });

        // Medido antes: scrollWidth 489 x clientWidth 416 (1280) e 412 (1440);
        // "Modo do chat" com 39 px de largura e 63 px de altura — 3 linhas —
        // e "Celular" cortado como "Celu".
        expect(
          medido.scrollWidth,
          `a barra transborda ${medido.scrollWidth - medido.clientWidth} px`
        ).toBeLessThanOrEqual(medido.clientWidth + 2);

        const quebrados = medido.labels.filter(label => label.linhas > 1);
        expect(quebrados.map(l => `${l.texto} (${l.linhas} linhas)`)).toEqual(
          []
        );

        const cortados = medido.labels.filter(label => label.cortado);
        expect(cortados.map(l => l.texto)).toEqual([]);
      });
    }
  }
});

// ---------------------------------------------------------------------------
// 4. Os cartoes de tema
// ---------------------------------------------------------------------------

test.describe('4. cartoes de tema (aba Aparencia)', () => {
  for (const viewport of VIEWPORTS) {
    for (const theme of THEMES) {
      test(`a descricao cabe em ate 2 linhas em ${viewport.width} (${theme})`, async ({
        page,
      }) => {
        await page.setViewportSize(viewport);
        await open(page, { theme, tab: 'appearance' });
        await page.waitForSelector('[data-testid="theme-light"]', {
          timeout: 20000,
        });

        const cartoes = await page.evaluate(() =>
          [...document.querySelectorAll('[data-testid^="theme-"]')].map(
            card => {
              const desc = card.querySelector('p');
              const lineHeight =
                parseFloat(getComputedStyle(desc).lineHeight) || 16;
              return {
                id: card.dataset.testid,
                largura: Math.round(card.getBoundingClientRect().width),
                texto: desc.innerText.trim(),
                linhas: Math.round(
                  desc.getBoundingClientRect().height / lineHeight
                ),
              };
            }
          )
        );

        expect(cartoes.length).toBe(3);
        // Medido antes: cartoes de 109 px; "O widget abre sempre claro." em 4
        // linhas e "Segue o tema do sistema de quem visita o site." em 6.
        const espremidos = cartoes.filter(card => card.linhas > 2);
        expect(
          espremidos.map(c => `${c.id}: ${c.linhas} linhas em ${c.largura}px`)
        ).toEqual([]);
      });
    }
  }
});

// ---------------------------------------------------------------------------
// 5. Contraste dos rotulos
// ---------------------------------------------------------------------------

test.describe('5. contraste dos rotulos do formulario', () => {
  // Os quatro que a instalacao mandou conferir, pelo texto exato.
  const NOMEADOS = [
    'Foto do atendimento',
    'Nome do site',
    'Domínio do website',
    'Centro de Ajuda',
  ];

  for (const theme of THEMES) {
    test(`os rotulos nomeados passam AA (${theme})`, async ({ page }) => {
      await open(page, { theme });

      const medidas = await page.evaluate(`(() => {
        ${CONTRAST_HELPERS}
        const alvos = ${JSON.stringify(NOMEADOS)};
        return [...document.querySelectorAll('label, h3')]
          .filter(el => el.children.length === 0)
          .filter(el => alvos.includes(el.innerText.trim()))
          .map(el => ({
            texto: el.innerText.trim(),
            razao: Number(_ratio(getComputedStyle(el).color, el).toFixed(2)),
          }));
      })()`);

      // Medido na instalacao ANTES de qualquer mudanca: 17,46:1 no claro e
      // 14,82:1 no escuro. Nenhum dos quatro estava abaixo de AA — este teste
      // e trava de regressao, e o relatorio diz isso com todas as letras.
      expect(medidas.map(m => m.texto).sort()).toEqual([...NOMEADOS].sort());
      const reprovados = medidas.filter(m => m.razao < 4.5);
      expect(reprovados.map(m => `"${m.texto}" ${m.razao}:1`)).toEqual([]);
    });

    test(`todo rotulo e texto de apoio do formulario passa AA (${theme})`, async ({
      page,
    }) => {
      await open(page, { theme });

      const medidas = await page.evaluate(`(() => {
        ${CONTRAST_HELPERS}
        // A coluna do formulario da aba "Geral" — a que a instalacao mandou
        // conferir. O preview ao lado tem tokens proprios (--wp-*) e nao e
        // formulario; a barra de abas e navegacao, nao rotulo.
        const form = document
          .querySelector('[data-testid="channel-avatar-field"]')
          .closest('div.flex-1');
        return [...form.querySelectorAll('label, p, h3, h4')]
          .filter(el => el.children.length === 0 && el.innerText.trim().length > 2)
          // Fora: texto dentro de <button>. O fundo ali e a cor de marca da
          // conta (medido: branco sobre #2dc46f da 2,27:1) — decisao de token
          // global, nao desta tela. Vai no relatorio, nao escondido aqui.
          .filter(el => !el.closest('button'))
          // Fora: sr-only. Sao 1x1 px recortados, ninguem enxerga.
          .filter(el => {
            const rect = el.getBoundingClientRect();
            return rect.width > 4 && rect.height > 4;
          })
          .map(el => {
            const cs = getComputedStyle(el);
            const size = parseFloat(cs.fontSize);
            const bold = parseInt(cs.fontWeight, 10) >= 700;
            return {
              texto: el.innerText.trim().slice(0, 48),
              razao: Number(_ratio(cs.color, el).toFixed(2)),
              // SC 1.4.3: texto grande (>= 24px, ou >= 18.66px em negrito)
              // passa com 3:1; o resto precisa de 4.5:1.
              minimo: size >= 24 || (bold && size >= 18.66) ? 3 : 4.5,
            };
          });
      })()`);

      expect(medidas.length).toBeGreaterThan(10);
      const reprovados = medidas.filter(m => m.razao < m.minimo);
      expect(
        reprovados.map(m => `"${m.texto}" ${m.razao}:1 (minimo ${m.minimo})`)
      ).toEqual([]);
    });
  }

  test('os rotulos da barra do preview passam AA nos dois temas', async ({
    page,
  }) => {
    for (const theme of THEMES) {
      await open(page, { theme });
      const medidas = await page.evaluate(`(() => {
        ${CONTRAST_HELPERS}
        const bar = document
          .querySelector('[data-testid="preview-chat-toggle"]')
          .closest('div.flex.items-center.justify-between');
        return [...bar.querySelectorAll('span')]
          .filter(el => el.children.length === 0 && el.innerText.trim().length > 2)
          .filter(el => {
            const rect = el.getBoundingClientRect();
            return rect.width > 4 && rect.height > 4;
          })
          .map(el => ({
            texto: el.innerText.trim(),
            razao: Number(_ratio(getComputedStyle(el).color, el).toFixed(2)),
          }));
      })()`);
      // Medido antes: "Modo do chat", "Escuro" e "Celular" em `text-n-slate-11`
      // davam 4,14:1 no tema claro — abaixo de AA por pouco, mas abaixo.
      const reprovados = medidas.filter(m => m.razao < 4.5);
      expect(
        reprovados.map(m => `${theme}: "${m.texto}" ${m.razao}:1`)
      ).toEqual([]);
    }
  });

  // Guarda contra teste que mede nada: se o calculo estivesse quebrado, os
  // testes acima ficariam verdes com QUALQUER cor. Aqui a condicao ruim e
  // forcada e o resultado TEM de ser reprovado.
  test('o medidor de contraste realmente reprova cor ruim', async ({
    page,
  }) => {
    await open(page, { theme: 'dark' });
    await page.addStyleTag({
      content: '.settings label { color: rgb(60, 65, 70) !important; }',
    });
    const reprovados = await page.evaluate(`(() => {
      ${CONTRAST_HELPERS}
      return [...document.querySelectorAll('.settings label')]
        .filter(el => el.children.length === 0 && el.innerText.trim().length > 2)
        .map(el => _ratio(getComputedStyle(el).color, el))
        .filter(razao => razao < 4.5).length;
    })()`);
    expect(reprovados).toBeGreaterThan(0);
  });
});
