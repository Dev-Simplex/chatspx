/**
 * Pré-condições:
 *  - localStorage limpo (chatspx_ai_onboarded === undefined)
 *  - Conversa carregada
 *
 * Verifica:
 *  - Coachmark aparece na primeira visita
 *  - Após "Quero conhecer" (microcopy v1.1), flag persiste e coachmark
 *    não reaparece em nova navegação
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const { loginAsAgent, openConversation } = require('./_helpers');

test.describe('Copilot onboarding — first time', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await page.evaluate(() => {
      window.localStorage.removeItem('chatspx_ai_onboarded');
      window.localStorage.removeItem('chatspx_ai_tour_completed');
      window.localStorage.removeItem('chatspx_ai_tour_step');
    });
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('shows coachmark on first visit and persists after Quero conhecer', async ({
    page,
  }) => {
    const coachmark = page.getByTestId('ai-onboarding-coachmark');
    await expect(coachmark).toBeVisible({ timeout: 4000 });

    await coachmark.getByRole('button', { name: /Quero conhecer/i }).click();
    await expect(coachmark).toBeHidden();

    const flag = await page.evaluate(() =>
      window.localStorage.getItem('chatspx_ai_onboarded')
    );
    expect(flag).toBe('true');

    // Reload — coachmark must NOT reappear
    await page.reload();
    await expect(coachmark).toBeHidden({ timeout: 4000 });
  });
});
