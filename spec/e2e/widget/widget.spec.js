const AxeBuilder = require('@axe-core/playwright').default;
const baseline = require('./baseline.json');
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const SDK_URL = 'http://127.0.0.1:3038';
const WIDGET_URL = 'http://127.0.0.1:3999';
const FROZEN_TIME = '2025-01-15T12:00:00.000Z';
const views = ['home', 'messages', 'prechat-form', 'unread', 'rich-types'];
const themes = ['light', 'dark'];
const viewportNames = ['desktop', 'mobile'];
const viewports = {
  desktop: { width: 1280, height: 720 },
  mobile: { width: 390, height: 844 },
};

// `rich-types` é um cenário de catálogo: ele existe para que os sete tipos
// ricos apareçam JUNTOS num único pixel-diff. Nos viewports reais eles não
// cabem — medido: 9 bolhas na conversa, apenas 3 a 5 dentro da área visível,
// e o snapshot gravava só as últimas. Altura maior aqui não é "viewport
// irreal": é o que faz o snapshot cobrir o que ele promete cobrir. A LARGURA
// continua sendo a real de cada viewport, que é o que governa o layout.
const viewportOverrides = {
  'rich-types': {
    desktop: { width: 1280, height: 1600 },
    mobile: { width: 390, height: 1500 },
  },
};

const viewportFor = (view, viewportName) =>
  viewportOverrides[view]?.[viewportName] ?? viewports[viewportName];

const anchorByView = {
  home: 'Estamos conectados.',
  messages: 'Mensagem determinística para o cenário.',
  'prechat-form': 'Conte um pouco sobre você.',
  unread: 'Resposta pendente número três.',
  'rich-types': 'Que nota você dá para o atendimento?',
};

// `rich-types` desenha na mesma rota de `messages`; o que muda é o conteúdo.
const routeByView = {
  home: 'home',
  messages: 'messages',
  'prechat-form': 'prechat-form',
  unread: 'unread-messages',
  'rich-types': 'messages',
};

// Os sete `content_type` que têm desenho próprio no widget, numa conversa só.
// O oitavo tipo — texto — já está coberto pelos outros quatro cenários: é o
// único que o harness alimentava antes desta matriz crescer.
//
// Regras que estas mensagens seguem, todas por determinismo do snapshot:
//   · `content` nunca vazio — `AgentMessage.shouldDisplayAgentMessage` esconde
//     a bolha inteira quando o conteúdo é vazio;
//   · nenhum `media_url` e nenhum link para fora — recurso de rede externa
//     dentro de um snapshot é falha intermitente esperando acontecer;
//   · `message_type: 3` (template), que é como o backend marca mensagem de bot.
const RICH_TYPE_MESSAGES = [
  {
    id: 201,
    content: 'Qual e-mail podemos usar para te responder?',
    content_type: 'input_email',
    created_at: 1736942400 - 700,
    message_type: 3,
    status: 'sent',
    content_attributes: {},
  },
  {
    id: 202,
    content: 'Escolha o assunto:',
    content_type: 'input_select',
    created_at: 1736942400 - 600,
    message_type: 3,
    status: 'sent',
    content_attributes: {
      items: [
        { title: 'Suporte técnico', value: 'suporte' },
        { title: 'Financeiro', value: 'financeiro' },
      ],
    },
  },
  {
    id: 203,
    content: 'Confira nossos planos:',
    content_type: 'cards',
    created_at: 1736942400 - 500,
    message_type: 3,
    status: 'sent',
    content_attributes: {
      items: [
        {
          title: 'Plano Essencial',
          description: 'Atendimento humano em horário comercial.',
          actions: [{ type: 'link', text: 'Ver detalhes', uri: '#essencial' }],
        },
      ],
    },
  },
  {
    id: 204,
    content: 'Preencha para abrirmos o chamado:',
    content_type: 'form',
    created_at: 1736942400 - 400,
    message_type: 3,
    status: 'sent',
    content_attributes: {
      button_label: 'Abrir chamado',
      items: [{ name: 'pedido', label: 'Número do pedido', type: 'text' }],
    },
  },
  {
    id: 205,
    content: 'Isto pode ajudar:',
    content_type: 'article',
    created_at: 1736942400 - 300,
    message_type: 3,
    status: 'sent',
    content_attributes: {
      items: [{ title: 'Como acompanhar meu pedido', link: '#artigo' }],
    },
  },
  {
    id: 206,
    content: 'Entramos na sala de atendimento:',
    content_type: 'integrations',
    created_at: 1736942400 - 200,
    message_type: 3,
    status: 'sent',
    content_attributes: { data: { room_name: 'sala-determinística' } },
  },
  {
    id: 207,
    content: 'Que nota você dá para o atendimento?',
    content_type: 'input_csat',
    created_at: 1736942400 - 100,
    message_type: 3,
    status: 'sent',
    content_attributes: { display_type: 'star' },
  },
];

const rgb = value =>
  value
    .match(/[\d.]+/g)
    .slice(0, 3)
    .map(Number);

const luminance = channels => {
  const linear = channels.map(channel => {
    const normalized = channel / 255;
    return normalized <= 0.04045
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
};

const contrastRatio = (foreground, background) => {
  const first = luminance(rgb(foreground));
  const second = luminance(rgb(background));
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
};

const computedContrast = async anchor => {
  const colors = await anchor.evaluate(element => {
    let backgroundElement = element;
    let background = getComputedStyle(backgroundElement).backgroundColor;
    while (
      backgroundElement.parentElement &&
      (background === 'rgba(0, 0, 0, 0)' || background === 'transparent')
    ) {
      backgroundElement = backgroundElement.parentElement;
      background = getComputedStyle(backgroundElement).backgroundColor;
    }
    return {
      background,
      foreground: getComputedStyle(element).color,
    };
  });
  return contrastRatio(colors.foreground, colors.background);
};

const freezeTime = async page => {
  await page.addInitScript(frozenTime => {
    const NativeDate = Date;
    const timestamp = NativeDate.parse(frozenTime);
    class FrozenDate extends NativeDate {
      constructor(...args) {
        super(...(args.length ? args : [timestamp]));
      }

      static now() {
        return timestamp;
      }
    }
    window.Date = FrozenDate;
  }, FROZEN_TIME);
};

const prepareScenario = async (page, view, theme, viewportName) => {
  await freezeTime(page);
  if (view === 'rich-types') {
    // Interceptar a API em vez de injetar no store depois de montado. A
    // injeção perdia uma corrida real: o widget refaz a carga da conversa
    // quando a configuração do SDK chega, e no primeiro cenário da suíte
    // (cache frio, tudo mais lento) isso acontecia DEPOIS da injeção — o
    // snapshot saía correto e a conversa aparecia vazia logo em seguida.
    // Servindo a lista pela rota, qualquer carga — a inicial ou a tardia —
    // devolve as mesmas sete mensagens, e não há ordem que quebre.
    await page.route('**/api/v1/widget/messages*', route =>
      route.fulfill({
        status: 200,
        contentType: 'application/json; charset=utf-8',
        body: JSON.stringify({
          payload: RICH_TYPE_MESSAGES,
          meta: { contact_last_seen_at: 1736942400 - 900 },
        }),
      })
    );
  }
  await page.setViewportSize(viewportFor(view, viewportName));
  await page.goto(`${HOST_URL}/?scenario=${view}&theme=${theme}`, {
    waitUntil: 'domcontentloaded',
  });
  await expect
    .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
      timeout: 30000,
    })
    .toBe(true);

  const iframe = page.locator('#chatwoot_live_chat_widget');
  const frame = page.frameLocator('#chatwoot_live_chat_widget');
  await expect(iframe).toBeAttached();
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

  if (view !== 'unread') {
    await page.evaluate(() => window.$chatwoot.toggle('open'));
    await expect(page.locator('#cw-widget-holder')).not.toHaveClass(
      /woot--hide/
    );
    await frame.locator('body').evaluate(async (_body, routeName) => {
      await window.WOOT_WIDGET.$router.replace({ name: routeName });
    }, routeByView[view]);
  } else {
    await expect(page.locator('#cw-widget-holder')).toHaveClass(
      /has-unread-view/
    );
  }

  await expect
    .poll(
      () =>
        frame
          .locator('body')
          .evaluate(() => window.WOOT_WIDGET?.$router?.currentRoute.value.name),
      { timeout: 30000 }
    )
    .toBe(routeByView[view]);
  const anchor = frame.getByText(anchorByView[view], { exact: true });
  await expect(anchor).toBeVisible();
  if (view === 'unread') {
    await expect(
      frame.getByText('Ver novas mensagens', { exact: true })
    ).toBeVisible();
  }
  await frame.locator('body').evaluate(() => document.fonts.ready);
  // ── FOCO, e por que ele entrou na preparação do cenário ────────────────────
  //
  // O composer recebe foco sozinho ao abrir a conversa, e o Chromium desenha o
  // anel `:focus-visible` dele — um retângulo escuro em volta do campo. Esse
  // anel entrava ou não no PNG conforme o instante em que o disparo do foco
  // caísse em relação ao screenshot: um estado não determinístico dentro de uma
  // suíte cujo método é justamente congelar tudo (o relógio, as animações, as
  // fontes) antes de fotografar.
  //
  // Ele passava despercebido porque o anel sozinho custa ~750 px num quadro de
  // 400×564, e o teto é `maxDiffPixelRatio: 0.01` = 2.256 px. Ou seja: a
  // variação existia e cabia embaixo da tolerância — até que uma mudança
  // legítima somasse a diferença dela e o quadro inteiro fosse reprovado, com o
  // anel no diff parecendo consequência dessa mudança. Foi o que aconteceu no
  // bloco 2.03, e custou três execuções do harness para separar as duas coisas.
  //
  // Tirar o foco antes de fotografar torna o estado explícito. O que se perde é
  // cobertura do anel de foco em pixel — que não era cobertura, era sorteio.
  await frame.locator('body').evaluate(() => document.activeElement?.blur());
  if (theme === 'dark') {
    await expect(frame.locator('#app > .dark')).toBeAttached();
  }
  return { anchor, frame, iframe };
};

views.forEach(view => {
  themes.forEach(theme => {
    viewportNames.forEach(viewportName => {
      const scenario = `${view}-${theme}-${viewportName}`;
      test(scenario, async ({ page }) => {
        const { anchor, frame } = await prepareScenario(
          page,
          view,
          theme,
          viewportName
        );
        const holder = page.locator('#cw-widget-holder');
        await expect
          .poll(async () => {
            const hostAnimations = await holder.evaluate(
              element =>
                element
                  .getAnimations({ subtree: true })
                  .filter(animation => animation.playState === 'running').length
            );
            const widgetAnimations = await frame
              .locator('body')
              .evaluate(
                () =>
                  document
                    .getAnimations()
                    .filter(animation => animation.playState === 'running')
                    .length
              );
            return hostAnimations + widgetAnimations;
          })
          .toBe(0);
        await expect(holder).toHaveScreenshot(`${scenario}.png`);

        const accessibility = await new AxeBuilder({ page })
          .include(['#chatwoot_live_chat_widget', '#app'])
          .analyze();
        const axeCounts = {
          critical: accessibility.violations.filter(
            violation => violation.impact === 'critical'
          ).length,
          serious: accessibility.violations.filter(
            violation => violation.impact === 'serious'
          ).length,
        };

        // ── PROVA DE VIDA DO AXE ──────────────────────────────────────────────
        //
        // Sem este trecho, a metade axe deste teste passa NO VÁCUO. As asserções
        // logo abaixo são todas da forma "medido <= teto", e o resultado que um
        // axe que não rodou devolve — `violations: []` — satisfaz TODOS os tetos,
        // em todos os cenários, para sempre. Três acidentes silenciosos levam a
        // esse resultado e nenhum deles quebra o teste: o `include` deixar de
        // casar (renomear o iframe basta), o axe não conseguir injetar dentro do
        // frame, ou a análise correr antes de o painel montar.
        //
        // As duas provas abaixo foram MEDIDAS antes de escritas, na corrida de
        // 28/08 (os 20 cenários), e não deduzidas da documentação:
        //
        //   · `passes.length` — quantas regras o axe avaliou e aprovou. Medido:
        //     de 14 (`unread-*`, o cenário mais pobre da matriz) a 32
        //     (`rich-types-*-desktop`). Zero significa que ele não avaliou nada.
        //
        //   · o `target` de cada nó. Num alvo dentro de iframe o axe devolve a
        //     CADEIA [seletor-do-frame, seletor-dentro-do-frame] — a forma real
        //     medida é `["#chatwoot_live_chat_widget", ".w-avatar__face"]`.
        //     Exigir a cadeia com o iframe do widget na cabeça é o que separa
        //     "o axe rodou DENTRO do widget" de "o axe rodou na página
        //     hospedeira e não viu o widget". Nós medidos por cenário: de 31 a
        //     245 — o piso de 10 abaixo tem 3x de folga sobre o menor.
        //
        // Verificado por mutação: trocando o `include` por um seletor que não
        // existe, o teste falha aqui, com a mensagem que nomeia o cenário.
        const nosAnalisados = [
          ...accessibility.passes,
          ...accessibility.violations,
          ...accessibility.incomplete,
        ].flatMap(regra => regra.nodes);
        const nosDentroDoWidget = nosAnalisados.filter(
          no =>
            Array.isArray(no.target) &&
            no.target.length > 1 &&
            no.target[0] === '#chatwoot_live_chat_widget'
        );
        expect(
          accessibility.passes.length,
          `o axe não avaliou regra nenhuma em ${scenario} — resultado vazio ` +
            `satisfaz qualquer teto, então os limites abaixo não mediriam nada`
        ).toBeGreaterThan(0);
        expect(
          nosDentroDoWidget.length,
          `o axe não analisou nós DENTRO do iframe do widget em ${scenario} ` +
            `(${nosAnalisados.length} nós no total) — o \`include\` não resolveu ` +
            `e o que estiver sendo medido não é o widget`
        ).toBeGreaterThanOrEqual(10);

        const ratio = await computedContrast(anchor);

        // TETO, não igualdade — autorizado pelo coordenador em 18/08.
        //
        // O aceite é "nenhuma REGRESSÃO crítica". `toEqual` também proíbe
        // MELHORAR: quando o bloco 1.06 deu nome acessível ao botão de fechar,
        // `critical` caiu de 1 para 0 em `home-*-mobile` e a régua reprovou a
        // correção — estava exigindo que a violação continuasse existindo.
        //
        // Com teto, regressão continua reprovando exatamente como antes; o que
        // deixa de reprovar é o conserto. E o número só desce por ATO
        // DELIBERADO: a melhoria passa, mas é impressa, para quem a viu decidir
        // baixar a linha de base em vez de o arquivo se ajustar sozinho.
        const axeEsperado = baseline.measurements[scenario].axe;
        Object.entries(axeCounts).forEach(([nivel, medido]) => {
          expect(
            medido,
            `violações ${nivel} de acessibilidade em ${scenario}: ` +
              `${medido} medidas contra o teto de ${axeEsperado[nivel]}`
          ).toBeLessThanOrEqual(axeEsperado[nivel]);
        });

        const melhorou = Object.entries(axeCounts).filter(
          ([nivel, medido]) => medido < axeEsperado[nivel]
        );
        if (melhorou.length) {
          // eslint-disable-next-line no-console
          console.log(
            `[axe] ${scenario} MELHOROU — ` +
              melhorou
                .map(
                  ([nivel, medido]) =>
                    `${nivel}: ${axeEsperado[nivel]} → ${medido}`
                )
                .join(', ') +
              `. Baixe a linha em spec/e2e/widget/baseline.json para travar o ganho.`
          );
        }

        expect(ratio).toBeCloseTo(baseline.measurements[scenario].contrast, 2);

        const geometry = await holder.evaluate(element => {
          const frameElement = element.querySelector('iframe');
          const holderRect = element.getBoundingClientRect();
          const iframeRect = frameElement.getBoundingClientRect();
          return {
            gap: Math.round(holderRect.height - iframeRect.height),
            holderWidth: holderRect.width,
            iframeWidth: iframeRect.width,
          };
        });

        if (viewportName === 'desktop') {
          expect(geometry.holderWidth).toBe(400);
        }
        if (view === 'unread') {
          expect(geometry.gap).toBe(4);
          if (viewportName === 'mobile') {
            expect(geometry.holderWidth).toBe(316);
            expect(geometry.iframeWidth).toBe(300);
          }
        }
      });
    });
  });
});

test('carrega SDK, entrypoint e host reais nas portas contratadas', async ({
  page,
}) => {
  await freezeTime(page);
  await page.goto(`${HOST_URL}/?scenario=home&theme=light`, {
    waitUntil: 'domcontentloaded',
  });
  await expect
    .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
      timeout: 30000,
    })
    .toBe(true);

  const resources = await page.evaluate(() =>
    performance.getEntriesByType('resource').map(entry => entry.name)
  );
  expect(resources).toContain(`${SDK_URL}/app/javascript/entrypoints/sdk.js`);
  expect(new URL(page.url()).port).toBe('8899');
  expect(new URL(await page.locator('iframe').getAttribute('src')).origin).toBe(
    WIDGET_URL
  );
  const snippetIsAfterContent = await page
    .locator('#chatwoot-snippet')
    .evaluate(snippet => {
      const siblings = [...snippet.parentElement.children];
      return (
        siblings.indexOf(document.querySelector('main')) <
        siblings.indexOf(snippet)
      );
    });
  expect(snippetIsAfterContent).toBe(true);
});

test('congela o relógio e alimenta o store determinístico', async ({
  page,
}) => {
  const { frame } = await prepareScenario(page, 'messages', 'light', 'desktop');
  const state = await frame.locator('body').evaluate(() => ({
    ids: Object.keys(
      window.WOOT_WIDGET.$store.state.conversation.conversations
    ),
    now: new Date().toISOString(),
  }));
  expect(state.ids).toEqual(['101', '102', '103', '104']);
  expect(state.now).toBe(FROZEN_TIME);
});

test('preserva a geometria original do unread no resize real', async ({
  page,
}) => {
  await prepareScenario(page, 'unread', 'light', 'desktop');
  await page.setViewportSize(viewports.mobile);

  await expect
    .poll(async () => {
      const geometry = await page
        .locator('#cw-widget-holder')
        .evaluate(element => {
          const frameElement = element.querySelector('iframe');
          const holderRect = element.getBoundingClientRect();
          const iframeRect = frameElement.getBoundingClientRect();
          return {
            gap: Math.round(holderRect.height - iframeRect.height),
            holder: Math.round(holderRect.width),
            iframe: Math.round(iframeRect.width),
            iframeHeight: Math.round(iframeRect.height),
          };
        });
      return geometry;
    })
    .toEqual({
      gap: 4,
      holder: 316,
      iframe: 300,
      // 278 → 302 no bloco 2.03. O que este teste guarda é a geometria que o
      // resize NÃO pode mexer — a largura do holder, a do iframe e o vão de
      // 4 px —, e os três continuam idênticos. A ALTURA é consequência do
      // conteúdo: o corpo do balão passou de 14/21 para 15/22 e a primeira das
      // três mensagens não lidas passou a ocupar duas linhas. Atualizar o
      // número é registrar a consequência; deixá-lo em 278 seria exigir que o
      // corpo do balão continuasse 14/21.
      iframeHeight: 302,
    });
});

// A matriz cresceu de 16 para 20 em 18/08, deliberadamente: `rich-types` ×
// 2 temas × 2 viewports. Motivo em `execucao/onda-1-bridge.md` §3 — o harness
// só alimentava `content_type: 'text'`, então os sete tipos ricos do widget
// não tinham cobertura de pixel nenhuma. Este número não se ajusta para fazer
// teste passar: se ele reprovar sem que alguém tenha decidido mudar a matriz,
// o cenário entrou sem querer, e é isso que se corrige.
test('baseline descreve exatamente a matriz de 20 cenários', async () => {
  const scenarios = views.flatMap(view =>
    themes.flatMap(theme =>
      viewportNames.map(viewportName => `${view}-${theme}-${viewportName}`)
    )
  );
  expect({
    version: baseline.version,
    views: baseline.views,
    themes: baseline.themes,
    viewports: baseline.viewports,
    scenarios: baseline.scenarios,
  }).toEqual({
    version: 1,
    views,
    themes,
    viewports,
    scenarios,
  });
  expect(Object.keys(baseline.measurements)).toEqual(scenarios);
  scenarios.forEach(scenario => {
    expect(baseline.measurements[scenario]).toEqual({
      axe: {
        critical: expect.any(Number),
        serious: expect.any(Number),
      },
      contrast: expect.any(Number),
    });
  });
});
