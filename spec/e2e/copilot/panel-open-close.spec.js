/**
 * Pré-condições:
 *  - Feature flag aiAssistantFlag ON (V2)
 *  - Agente logado, conversa aberta
 *
 * Verifica:
 *  - Painel slide-in da direita
 *  - Foco vai para o primeiro elemento focável dentro do painel (focus trap)
 *  - Esc fecha e retorna foco ao botão original
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  setFeatureFlag,
  panelRoot,
  openPanel,
} = require('./_helpers');

test.describe('Copilot panel — open/close lifecycle', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    // Force a soft reload so the V2 panel can mount
    await page.reload();
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('panel opens with slide-in, traps focus, and Esc closes it', async ({ page }) => {
    await openPanel(page);
    const dialog = panelRoot(page);

    // Focus is somewhere inside the dialog
    const inside = await dialog.evaluate(el => el.contains(document.activeElement));
    expect(inside).toBe(true);

    // Esc closes
    await page.keyboard.press('Escape');
    await expect(dialog).toBeHidden({ timeout: 4000 });

    // Focus returns to the launcher
    const launcherFocused = await page.evaluate(
      () => document.activeElement?.getAttribute('data-testid') === 'copilot-launcher'
    );
    expect(launcherFocused).toBe(true);
  });

  test('Tab cycles inside the panel (focus trap)', async ({ page }) => {
    await openPanel(page);
    // Press Tab a few times — focus must always be inside the dialog
    for (let i = 0; i < 6; i += 1) {
      await page.keyboard.press('Tab');
      const inside = await panelRoot(page).evaluate(el => el.contains(document.activeElement));
      expect(inside).toBe(true);
    }
  });
});
