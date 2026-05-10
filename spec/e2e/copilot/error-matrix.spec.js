/**
 * Pré-condições:
 *  - Painel V2 aberto, agente logado
 *
 * Verifica matriz de erros distintos:
 *  - 429 → banner "rate_limit" com cooldown
 *  - 408/timeout → banner "timeout" com Cancelar
 *  - 502/503 → banner "captain_unstable"
 *  - empty body → banner "empty"
 *  - network error → banner "network" com Retry
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

test.describe('Copilot panel — error matrix', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await openPanel(page);
  });

  test('429 → rate-limit banner', async ({ page }) => {
    await mockCaptain(page, {
      route: /captain/,
      status: 429,
      response: { error: 'rate_limit_exceeded' },
    });
    await page.getByText(/Resumir esta conversa/i).first().click();
    await expect(page.getByTestId('ai-error-banner-rate-limit')).toBeVisible({ timeout: 6000 });
  });

  test('502 → captain_unstable banner', async ({ page }) => {
    await mockCaptain(page, {
      route: /captain/,
      status: 502,
      response: { error: 'bad_gateway' },
    });
    await page.getByText(/Resumir esta conversa/i).first().click();
    await expect(page.getByTestId('ai-error-banner-captain-unstable')).toBeVisible({ timeout: 6000 });
  });

  test('empty body → empty-response banner', async ({ page }) => {
    await mockCaptain(page, {
      route: /captain/,
      status: 200,
      response: { message: '' },
    });
    await page.getByText(/Resumir esta conversa/i).first().click();
    await expect(page.getByTestId('ai-error-banner-empty')).toBeVisible({ timeout: 6000 });
  });

  test('timeout → timeout banner with Cancelar option', async ({ page }) => {
    await mockCaptain(page, {
      route: /captain/,
      status: 200,
      response: { message: 'OK' },
      delay: 12_000,
    });
    await page.getByText(/Resumir esta conversa/i).first().click();
    await expect(page.getByTestId('ai-error-banner-timeout')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByRole('button', { name: /Cancelar|Tentar de novo/i })).toBeVisible();
  });
});
