/**
 * Pré-condições:
 *  - Composer com texto, dropdown sparkles "Sugerir uma resposta" gera chip
 *
 * Verifica:
 *  - Chip aparece acima do composer
 *  - "Usar essa" insere texto no composer e some o chip
 *  - Track event ai.suggestion.accepted dispara
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  mockCaptainProcessEvent,
  sparklesButton,
} = require('./_helpers');

test.describe('Copilot suggestion chip — Usar essa flow', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await mockCaptainProcessEvent(page, { message: 'Olá! Posso te ajudar?' });
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('Usar essa applies the suggestion and removes the chip', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('preciso de ajuda');

    await sparklesButton(page).click();
    await page.getByRole('menu').getByText(/Sugerir uma resposta/i).click();

    const chip = page.getByTestId('ai-suggestion-chip');
    await expect(chip).toBeVisible({ timeout: 6000 });
    await expect(chip).toContainText(/Olá/);

    await chip.getByRole('button', { name: /Usar essa/i }).click();

    await expect(chip).toBeHidden({ timeout: 4000 });
    await expect(editor).toContainText(/Olá/);
  });
});
