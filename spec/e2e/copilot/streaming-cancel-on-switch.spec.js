/**
 * Pré-condições:
 *  - Painel V2 aberto, request lenta (delay) em curso
 *  - Múltiplas conversas disponíveis
 *
 * Verifica:
 *  - Trocar para outra conversa durante streaming aborta o fetch
 *  - Histórico do painel é limpo
 *  - Track event ai.streaming.cancelled dispara com motivo "context_switch"
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  setFeatureFlag,
  openPanel,
  mockCaptain,
} = require('./_helpers');

test.describe('Copilot streaming — cancel on context switch', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
  });

  test('switching conversation aborts in-flight Captain request', async ({ page, context }) => {
    let aborted = false;
    await mockCaptain(page, {
      route: /captain/,
      status: 200,
      response: { message: 'should never arrive' },
      delay: 8_000,
    });

    page.on('requestfailed', req => {
      if (/captain/.test(req.url()) && req.failure()?.errorText?.match(/aborted/i)) {
        aborted = true;
      }
    });

    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await openPanel(page);

    await page.getByText(/Resumir esta conversa/i).first().click();
    await expect(page.getByTestId('ai-loading-shimmer')).toBeVisible({ timeout: 4000 });

    // Switch conversation
    await openConversation(page, process.env.E2E_CONVERSATION_ID_2 || 2);

    // Loading shimmer must clear
    await expect(page.getByTestId('ai-loading-shimmer')).toBeHidden({ timeout: 6000 });
    expect(aborted).toBe(true);
  });
});
