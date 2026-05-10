/**
 * Pré-condições:
 *  - Chip mostrando uma sugestão
 *
 * Verifica:
 *  - "Descartar" remove o chip
 *  - Composer mantém o texto original
 *  - Esc dentro do chip também descarta
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  mockCaptainProcessEvent,
  sparklesButton,
} = require('./_helpers');

test.describe('Copilot suggestion chip — discard flows', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await mockCaptainProcessEvent(page, { message: 'Sugestão gerada' });
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('Descartar removes chip and preserves composer text', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('rascunho original');

    await sparklesButton(page).click();
    await page.getByRole('menu').getByText(/Sugerir uma resposta/i).click();

    const chip = page.getByTestId('ai-suggestion-chip');
    await expect(chip).toBeVisible({ timeout: 6000 });
    await chip.getByRole('button', { name: /Descartar/i }).click();
    await expect(chip).toBeHidden();
    await expect(editor).toContainText('rascunho original');
  });

  test('Esc inside chip also discards', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('outro rascunho');

    await sparklesButton(page).click();
    await page.getByRole('menu').getByText(/Sugerir uma resposta/i).click();

    const chip = page.getByTestId('ai-suggestion-chip');
    await expect(chip).toBeVisible({ timeout: 6000 });
    await chip.focus();
    await page.keyboard.press('Escape');
    await expect(chip).toBeHidden();
  });
});
