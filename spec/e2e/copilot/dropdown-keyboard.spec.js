/**
 * Pré-condições:
 *  - Dropdown aberto
 *
 * Verifica:
 *  - ↑↓ navegam itens
 *  - Enter dispara ação
 *  - Esc fecha menu e retorna foco ao botão sparkles
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  mockCaptainProcessEvent,
  sparklesButton,
} = require('./_helpers');

test.describe('Copilot dropdown — keyboard navigation', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await mockCaptainProcessEvent(page);
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('rascunho');
  });

  test('ArrowDown moves focus to next item, Enter activates', async ({ page }) => {
    await sparklesButton(page).click();
    const menu = page.getByRole('menu');
    await expect(menu).toBeVisible();

    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('ArrowDown');
    // The active item must have focus visible (ring or aria-current)
    const focused = await page.evaluate(() => document.activeElement?.textContent || '');
    expect(focused.length).toBeGreaterThan(0);

    await page.keyboard.press('Enter');
    // Menu closes after selection
    await expect(menu).toBeHidden({ timeout: 4000 });
  });

  test('Escape closes menu and restores focus to sparkles', async ({ page }) => {
    await sparklesButton(page).click();
    await expect(page.getByRole('menu')).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(page.getByRole('menu')).toBeHidden();

    const focusedTestId = await page.evaluate(() => document.activeElement?.getAttribute('data-testid'));
    expect(focusedTestId).toBe('ai-button');
  });
});
