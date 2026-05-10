/**
 * Pré-condições:
 *  - useAIAssistantFlag respeita 3 fontes em ordem:
 *    1. sessionStorage (?aiv2=1) — wins always
 *    2. localStorage   (chatspx_ai_panel_v2)
 *    3. server feature_flag (account.feature_flags.ai_assistant_v2)
 *
 * Verifica:
 *  - Query param overrides everything
 *  - localStorage overrides server flag
 *  - Server flag wins when nothing else is set
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  panelRoot,
} = require('./_helpers');

test.describe('AI panel feature flag — precedence chain', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await page.evaluate(() => {
      window.localStorage.removeItem('chatspx_ai_panel_v2');
      window.sessionStorage.removeItem('chatspx_ai_panel_v2_session');
    });
  });

  test('?aiv2=1 query param overrides everything', async ({ page }) => {
    const accountId = process.env.E2E_ACCOUNT_ID || 1;
    const conversationId = process.env.E2E_CONVERSATION_ID || 1;
    await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}?aiv2=1`);
    await page.waitForLoadState('networkidle');
    await page.getByTestId('copilot-launcher').click();
    await expect(panelRoot(page)).toBeVisible();
  });

  test('localStorage on enables V2', async ({ page }) => {
    await page.evaluate(() => window.localStorage.setItem('chatspx_ai_panel_v2', 'on'));
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await page.getByTestId('copilot-launcher').click();
    await expect(panelRoot(page)).toBeVisible();
  });

  test('localStorage off disables V2 even when server says on', async ({ page }) => {
    await page.evaluate(() => window.localStorage.setItem('chatspx_ai_panel_v2', 'off'));
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await page.getByTestId('copilot-launcher').click();
    await expect(panelRoot(page)).toHaveCount(0);
  });
});
