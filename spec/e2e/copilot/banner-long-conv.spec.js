/**
 * Pré-condições:
 *  - Conversa com >=10 mensagens reais ou stub
 *  - useSmartSuggestions ativo, dismissed list vazia
 *
 * Verifica:
 *  - Smart banner "Conversa longa (N msgs). Quer um resumo?" aparece
 *  - Botão "Resumir agora" dispara mesma ação que quick prompt summarize
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  setFeatureFlag,
  openPanel,
  mockCaptainProcessEvent,
} = require('./_helpers');

test.describe('Copilot smart banner — long conversation', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    await page.evaluate(() => {
      window.localStorage.removeItem('chatspx_ai_dismissed_suggestions');
    });
    await mockCaptainProcessEvent(page, { message: 'Resumo da conversa' });
    // Use a conversation seeded with >=10 messages, fixture-controlled.
    await openConversation(page, process.env.E2E_LONG_CONVERSATION_ID || 1);
    await openPanel(page);
  });

  test('shows long-thread banner and CTA dispatches summarize', async ({ page }) => {
    const banner = page.getByTestId('ai-smart-banner-long-thread');
    await expect(banner).toBeVisible({ timeout: 4000 });
    await expect(banner).toContainText(/Conversa longa/i);

    await banner.getByRole('button', { name: /Resumir agora/i }).click();
    await expect(page.getByTestId('ai-loading-shimmer')).toBeVisible({ timeout: 4000 });
  });
});
