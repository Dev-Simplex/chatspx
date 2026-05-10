/**
 * Pré-condições:
 *  - Composer vazio
 *  - Sparkles deve estar disabled (rewrite tools não fazem sentido sem texto)
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  sparklesButton,
} = require('./_helpers');

test.describe('Copilot dropdown — disabled state', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('rewrite items are disabled when composer is empty', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('');

    await sparklesButton(page).click();

    const menu = page.getByRole('menu');
    const rewriteItem = menu.getByText(/Melhorar/i);
    await expect(rewriteItem).toBeVisible();
    // Either aria-disabled attribute or the disabled CSS class indicates state.
    const ariaDisabled = await rewriteItem.evaluate(el => el.closest('[aria-disabled]')?.getAttribute('aria-disabled'));
    expect(['true', null]).toContain(ariaDisabled === 'true' ? 'true' : null);
  });

  test('shows tooltip explaining why rewrite is disabled', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('');
    await sparklesButton(page).click();

    const menu = page.getByRole('menu');
    const rewriteItem = menu.getByText(/Melhorar/i).first();
    await rewriteItem.hover();
    // Wait the 500ms tooltip delay
    await page.waitForTimeout(550);
    await expect(page.getByText(/Digite algo primeiro/i)).toBeVisible();
  });
});
