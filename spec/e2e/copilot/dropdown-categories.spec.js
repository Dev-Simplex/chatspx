/**
 * Pré-condições:
 *  - Agente logado, conversa aberta com texto no composer
 *  - Feature flag legado (V1) ativa, OU painel V2 desligado
 *
 * Verifica:
 *  - Dropdown sparkles renderiza 3 seções com headers cinzas em pt-BR
 *  - Microcopy verbo+objeto presente
 *  - Ordem das seções: ENTENDER → AJUSTAR → CRIAR
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  mockCaptainProcessEvent,
  sparklesButton,
} = require('./_helpers');

test.describe('Copilot dropdown — categories', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await mockCaptainProcessEvent(page);
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
  });

  test('renders three sections with pt-BR headers in order', async ({ page }) => {
    // Type something so the dropdown's rewrite items aren't disabled.
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('rascunho de teste');

    await sparklesButton(page).click();

    const menu = page.getByRole('menu');
    await expect(menu).toBeVisible();

    const headers = await menu.locator('[role="presentation"], header, .copilot-section-header').allInnerTexts();
    const haystack = headers.join('|').toUpperCase();

    expect(haystack).toContain('ENTENDER');
    expect(haystack).toContain('AJUSTAR');
    expect(haystack).toContain('CRIAR');

    const indexEntender = haystack.indexOf('ENTENDER');
    const indexAjustar = haystack.indexOf('AJUSTAR');
    const indexCriar = haystack.indexOf('CRIAR');
    expect(indexEntender).toBeLessThan(indexAjustar);
    expect(indexAjustar).toBeLessThan(indexCriar);
  });

  test('rewrite items show verb+object microcopy in pt-BR', async ({ page }) => {
    const editor = page.locator('.ProseMirror').first();
    await editor.click();
    await editor.fill('rascunho');
    await sparklesButton(page).click();

    const menu = page.getByRole('menu');
    await expect(menu.getByText(/Melhorar/i)).toBeVisible();
    await expect(menu.getByText(/mais formal/i)).toBeVisible();
    await expect(menu.getByText(/Encurtar/i)).toBeVisible();
  });
});
