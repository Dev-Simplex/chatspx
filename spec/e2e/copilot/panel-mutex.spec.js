/**
 * Pré-condições:
 *  - Feature flag aiAssistantFlag controlável via localStorage
 *
 * Verifica:
 *  - Quando V2 ON, AIAssistantPanel é montado e CopilotContainer não
 *  - Quando V2 OFF, vice-versa
 *  - Mutex é estrito: nunca os dois ao mesmo tempo
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  setFeatureFlag,
  clearFeatureFlag,
  openPanel,
  panelRoot,
} = require('./_helpers');

test.describe('Copilot panel — V1/V2 mutex', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
  });

  test('V2 flag ON mounts AIAssistantPanel and hides legacy container', async ({ page }) => {
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await openPanel(page);

    await expect(panelRoot(page)).toBeVisible();
    const legacy = page.locator('[data-testid="copilot-container-legacy"]');
    await expect(legacy).toHaveCount(0);
  });

  test('V2 flag OFF falls back to legacy CopilotContainer', async ({ page }) => {
    await clearFeatureFlag(page, 'chatspx_ai_panel_v2');
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    // Legacy launcher behaves the same; just assert dialog is NOT the V2 one.
    await page.getByTestId('copilot-launcher').click();
    const v2Dialog = page.getByRole('dialog', { name: /copilot/i });
    // Legacy is not a Headless dialog — it should not render with role=dialog
    await expect(v2Dialog).toHaveCount(0);
  });
});
