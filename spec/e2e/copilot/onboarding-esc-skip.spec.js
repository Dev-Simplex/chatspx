/**
 * Pré-condições:
 *  - localStorage limpo
 *
 * Verifica:
 *  - Esc dispensa coachmark sem persistir flag
 *  - Próximo carregamento mostra coachmark de novo
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
} = require('./_helpers');

test.describe('Copilot onboarding — Esc behavior', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await page.evaluate(() => {
      window.localStorage.removeItem('chatspx_ai_onboarded');
    });
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('Esc dismisses without persisting and coachmark reappears', async ({ page }) => {
    const coachmark = page.getByTestId('ai-onboarding-coachmark');
    await expect(coachmark).toBeVisible({ timeout: 4000 });

    await page.keyboard.press('Escape');
    await expect(coachmark).toBeHidden();

    const flag = await page.evaluate(() => window.localStorage.getItem('chatspx_ai_onboarded'));
    expect(flag).toBeNull();

    await page.reload();
    await expect(coachmark).toBeVisible({ timeout: 4000 });
  });
});
