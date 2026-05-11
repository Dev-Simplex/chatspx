/**
 * Pré-condições:
 *  - Painel V2 aberto, smart banner visível
 *
 * Verifica:
 *  - "Dispensar" oculta banner imediatamente
 *  - localStorage.chatspx_ai_dismissed_suggestions persiste por conversa
 *  - Próxima abertura da MESMA conversa não mostra mais
 *  - Outra conversa ainda pode mostrar
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  setFeatureFlag,
  openPanel,
} = require('./_helpers');

test.describe('Copilot smart banner — dismiss persistence', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    await page.evaluate(() => {
      window.localStorage.removeItem('chatspx_ai_dismissed_suggestions');
    });
  });

  test('dismiss persists per conversation', async ({ page }) => {
    const conversationId = process.env.E2E_LONG_CONVERSATION_ID || 1;
    await openConversation(page, conversationId);
    await openPanel(page);

    const banner = page.getByTestId('ai-smart-banner-long-thread');
    await expect(banner).toBeVisible({ timeout: 4000 });

    await banner.getByRole('button', { name: /Dispensar/i }).click();
    await expect(banner).toBeHidden();

    const stored = await page.evaluate(() =>
      window.localStorage.getItem('chatspx_ai_dismissed_suggestions')
    );
    expect(stored).toContain(String(conversationId));

    // Reload — banner stays hidden
    await page.reload();
    await openPanel(page);
    await expect(page.getByTestId('ai-smart-banner-long-thread')).toBeHidden();
  });
});
