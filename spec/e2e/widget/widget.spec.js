const AxeBuilder = require('@axe-core/playwright').default;
const baseline = require('./baseline.json');
const { test, expect } = require('../fixtures');

const HOST_URL = 'http://127.0.0.1:8899';
const SDK_URL = 'http://127.0.0.1:3038';
const WIDGET_URL = 'http://127.0.0.1:3999';
const FROZEN_TIME = '2025-01-15T12:00:00.000Z';
const views = ['home', 'messages', 'prechat-form', 'unread'];
const themes = ['light', 'dark'];
const viewportNames = ['desktop', 'mobile'];
const viewports = {
  desktop: { width: 1280, height: 720 },
  mobile: { width: 390, height: 844 },
};

const anchorByView = {
  home: 'Estamos conectados.',
  messages: 'Mensagem determinística para o cenário.',
  'prechat-form': 'Conte um pouco sobre você.',
  unread: 'Resposta pendente número três.',
};

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
  await page.setViewportSize(viewports[viewportName]);
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
    }, view);
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
    .toBe(view === 'unread' ? 'unread-messages' : view);
  const anchor = frame.getByText(anchorByView[view], { exact: true });
  await expect(anchor).toBeVisible();
  if (view === 'unread') {
    await expect(
      frame.getByText('Ver novas mensagens', { exact: true })
    ).toBeVisible();
  }
  await frame.locator('body').evaluate(() => document.fonts.ready);
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
        const ratio = await computedContrast(anchor);
        expect(axeCounts).toEqual(baseline.measurements[scenario].axe);
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
      iframeHeight: 278,
    });
});

test('baseline descreve exatamente a matriz de 16 cenários', async () => {
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
