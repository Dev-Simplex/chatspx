/**
 * BLOCO 2.08 — movimento, `prefers-reduced-motion`, `prefers-contrast` e
 * `forced-colors`, medidos no navegador que os implementa.
 *
 * ── Por que NADA disto pode ser verificado em jsdom ──────────────────────────
 *
 * Os três são media queries: quem os resolve é o motor de estilo, e jsdom não
 * tem um. Lá `getComputedStyle` devolve o que foi escrito no atributo, não o
 * que a cascata produziu — então uma regra dentro de `@media (forced-colors:
 * active)` é indistinguível de uma regra que não existe.
 *
 * O Playwright emula os três de verdade, no nível do Chromium (`reducedMotion`,
 * `contrast`, `forcedColors`), e não por injeção de CSS. É a mesma coisa que o
 * visitante liga no sistema operacional dele.
 *
 * ── O QUE ESTE ARQUIVO RECUSA A ACEITAR COMO PROVA ───────────────────────────
 *
 * `prefers-reduced-motion` **não é "desligar animação"**. É *entregar o mesmo
 * estado final sem o percurso*. Um teste que só verificasse
 * `animation-name: none` passaria com a interface quebrada — com o botão
 * invisível, ou com o clique não levando a lugar nenhum, que é justamente o
 * defeito que a leitura preguiçosa dessa preferência produz.
 *
 * Por isso cada exame daqui mede o ESTADO FINAL, e o percurso só depois.
 */
/* eslint-disable no-console -- os valores medidos são a saída útil do arquivo,
   lidos por quem roda e colados no relatório do bloco. */
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const FROZEN_EPOCH = 1736942400;
const DISTANCIA_DO_FIM = 300;
const TOLERANCIA_FIM = 80;

const MUITAS_MENSAGENS = Array.from({ length: 40 }, (_, i) => ({
  id: 500 + i,
  content: `Mensagem determinística número ${i + 1} da lista longa.`,
  content_type: 'text',
  created_at: FROZEN_EPOCH - (40 - i) * 60,
  message_type: i % 2,
  status: 'sent',
  ...(i % 2
    ? {
        sender: {
          id: 7,
          name: 'Marina Lima',
          available_name: 'Marina Lima',
          availability_status: 'online',
        },
      }
    : {}),
}));

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

// ── COMO A PREFERÊNCIA É LIGADA, e por que NÃO por `test.use` ────────────────
//
// `test.use({ reducedMotion, forcedColors, contrast })` NÃO chega ao contexto
// no projeto `widget` deste repositório — medido: com ele, as três consultas
// respondem `false` dentro E fora do iframe, e o teste vira uma medição do
// estado padrão com nome de acessibilidade. `page.emulateMedia()` funciona, e
// as mesmas três respondem `true`.
//
// Isso não é preferência de estilo: é a diferença entre emular e achar que
// emulou. Um arquivo escrito com `test.use` passaria em TODAS as asserções que
// esperassem o comportamento padrão e falharia só nas que exigem a preferência
// — que é o que aconteceu aqui na primeira corrida.
const abrir = async (page, tema = 'light', midia = {}) => {
  await page.emulateMedia(midia);
  await page.route('**/api/v1/widget/messages*', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify({
        payload: MUITAS_MENSAGENS,
        meta: { contact_last_seen_at: FROZEN_EPOCH - 3000 },
      }),
    })
  );
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
    frame.getByText('Mensagem determinística número 40 da lista longa.', {
      exact: true,
    })
  ).toBeVisible();
  return frame;
};

const distanciaDoFim = frame =>
  frame
    .locator('.conversation-wrap')
    .evaluate(el =>
      Math.round(el.scrollHeight - el.scrollTop - el.clientHeight)
    );

const subir = async frame => {
  await frame.locator('.conversation-wrap').evaluate((el, folga) => {
    el.scrollTop = el.scrollHeight - el.clientHeight - folga;
  }, DISTANCIA_DO_FIM);
  await expect.poll(() => distanciaDoFim(frame)).toBe(DISTANCIA_DO_FIM);
};

// ── `prefers-reduced-motion` ─────────────────────────────────────────────────

const MENOS_MOVIMENTO = { reducedMotion: 'reduce' };

test.describe('2.08 — movimento reduzido', () => {
  test('o clique no "descer" CHEGA AO FIM — o destino não é opcional', async ({
    page,
  }) => {
    // ESTE é o exame do bloco. A leitura errada de `prefers-reduced-motion`
    // ("cancele o movimento") produziria um botão que não leva a lugar nenhum,
    // e passaria num teste que só olhasse `animation`.
    const frame = await abrir(page, 'light', MENOS_MOVIMENTO);
    await subir(frame);

    await frame.locator('.conversation--descer button').click();

    await expect
      .poll(() => distanciaDoFim(frame))
      .toBeLessThanOrEqual(TOLERANCIA_FIM);
  });

  test('o botão está VISÍVEL e opaco — o estado final da animação, sem o percurso', async ({
    page,
  }) => {
    const frame = await abrir(page, 'light', MENOS_MOVIMENTO);
    await subir(frame);

    const botao = frame.locator('.conversation--descer');
    const estilo = await botao.evaluate(el => {
      const e = getComputedStyle(el);
      return {
        opacity: Number(e.opacity),
        duracao: e.animationDuration,
        transform: e.transform,
      };
    });
    console.log(
      `[movimento reduzido] opacity=${estilo.opacity} ` +
        `animation-duration=${estilo.duracao} transform=${estilo.transform}`
    );

    // O estado final: opaco e na posição de repouso. Se a implementação tivesse
    // apenas removido a animação a meio caminho, ou deixado o `translateY(8px)`
    // de entrada, isto pegaria.
    await expect(botao).toBeVisible();
    expect(estilo.opacity).toBe(1);
    expect(['none', 'matrix(1, 0, 0, 1, 0, 0)']).toContain(estilo.transform);
    // E o percurso, aí sim, não existe.
    expect(estilo.duracao).toBe('0s');
  });
});

test.describe('2.08 — sem a preferência, o percurso existe', () => {
  test('a animação de entrada tem duração', async ({ page }) => {
    // O par do exame acima. Sem ele, "duração 0s" seria satisfeito por um
    // widget que simplesmente não anima nada nunca — e aí o bloco não teria
    // feito nada.
    const frame = await abrir(page, 'light', {
      reducedMotion: 'no-preference',
    });
    await subir(frame);

    const duracao = await frame
      .locator('.conversation--descer')
      .evaluate(el => getComputedStyle(el).animationDuration);
    console.log(`[movimento normal] animation-duration=${duracao}`);

    expect(duracao).not.toBe('0s');
  });
});

// ── `forced-colors` ──────────────────────────────────────────────────────────

test.describe('2.08 — `forced-colors`', () => {
  test('a textura sai, e o balão ganha a borda que o sistema pinta', async ({
    page,
  }) => {
    const frame = await abrir(page, 'light', { forcedColors: 'active' });

    const medido = await frame
      .locator('.conversation--container')
      .evaluate(container => {
        const balao = container.querySelector('.chat-bubble.agent');
        return {
          textura: getComputedStyle(container, '::before').display,
          bordaLargura: getComputedStyle(balao).borderTopWidth,
          bordaCor: getComputedStyle(balao).borderTopColor,
          fundoBalao: getComputedStyle(balao).backgroundColor,
          fundoLista: getComputedStyle(container).backgroundColor,
        };
      });
    console.log(
      `[forced-colors] textura=${medido.textura} ` +
        `borda=${medido.bordaLargura} ${medido.bordaCor} ` +
        `balão=${medido.fundoBalao} lista=${medido.fundoLista}`
    );

    // 1. A textura sai. Sob cores forçadas ela viraria rabisco na MESMA cor do
    //    texto, competindo com ele.
    expect(medido.textura).toBe('none');
    // 2. A borda existe e não é transparente — é ela que separa o balão da
    //    lista agora que o sistema pintou os dois com a mesma cor de canvas e
    //    que o 2.03 tirou a sombra.
    expect(medido.bordaLargura).toBe('1px');
    expect(medido.bordaCor).not.toBe('rgba(0, 0, 0, 0)');
    // 3. E é a cor do SISTEMA, não a nossa: sob `forced-colors` o Chromium
    //    substitui `CanvasText` pelo par escolhido pelo visitante, então este
    //    valor não pode ser o `--slate-7` do tema escuro.
    expect(medido.bordaCor).not.toBe('rgb(67, 72, 78)');
  });
});

// ── `prefers-contrast: more` ─────────────────────────────────────────────────

const MINIMO_NAO_TEXTO = 3; // WCAG 1.4.11

['light', 'dark'].forEach(tema => {
  test.describe(`2.08 — \`prefers-contrast: more\` (${tema})`, () => {
    test(`a borda do balão passa a cumprir ${MINIMO_NAO_TEXTO}:1`, async ({
      page,
    }) => {
      // A promessa que o 2.03 deixou escrita e adiou: sem a preferência a borda
      // mede 1,72:1 no escuro, abaixo de 1.4.11, e subir isso para todo mundo
      // seria um contorno visível em volta de cada balão — decisão de desenho
      // que o plano não tomou. Com a preferência LIGADA, o visitante tomou.
      const frame = await abrir(page, tema, { contrast: 'more' });

      const medido = await frame
        .locator('.conversation--container')
        .evaluate(container => {
          const balao = container.querySelector('.chat-bubble.agent');
          return {
            superficie: getComputedStyle(container).backgroundColor,
            corDaBorda: getComputedStyle(balao).borderTopColor,
            textura: Number(getComputedStyle(container, '::before').opacity),
          };
        });
      const razao = contraste(rgb(medido.superficie), rgb(medido.corDaBorda));
      console.log(
        `[contraste alto ${tema}] superfície=${medido.superficie} ` +
          `borda=${medido.corDaBorda} razão=${razao.toFixed(3)}:1 ` +
          `textura-opacity=${medido.textura}`
      );

      expect(
        razao,
        `a borda do balão mede ${razao.toFixed(3)}:1 contra a superfície da ` +
          `lista; sob \`prefers-contrast: more\` o mínimo é ${MINIMO_NAO_TEXTO}:1`
      ).toBeGreaterThanOrEqual(MINIMO_NAO_TEXTO);
      // E a textura sai do caminho: ruído de fundo sob a mesma superfície onde
      // o texto vive é o oposto do que a preferência pede.
      expect(medido.textura).toBe(0);
    });
  });
});
