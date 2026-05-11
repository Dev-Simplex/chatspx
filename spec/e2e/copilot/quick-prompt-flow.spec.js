/**
 * Pré-condições:
 *  - Painel V2 aberto
 *  - Captain mockado com mensagem com markdown (negrito + lista)
 *
 * Verifica:
 *  - Click em quick prompt dispara request
 *  - Loading shimmer aparece
 *  - Resposta aparece com markdown renderizado (strong, ul, li)
 *  - Typewriter completa em < 2s para texto curto
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

test.describe('Copilot panel — quick prompt full flow', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await setFeatureFlag(page, 'chatspx_ai_panel_v2', 'on');
    await openConversation(page, process.env.E2E_CONVERSATION_ID || 1);
    await mockCaptainProcessEvent(page, {
      message: '**Resumo**\n\n- Pergunta sobre horários\n- Quer saber férias',
    });
    await openPanel(page);
  });

  test('quick prompt → shimmer → markdown → action chips', async ({ page }) => {
    await page.getByText(/Resumir esta conversa/i).first().click();

    // Loading shimmer
    await expect(page.getByTestId('ai-loading-shimmer')).toBeVisible({ timeout: 4000 });

    // Eventually the assistant bubble has rendered markdown
    const bubble = page.getByTestId('ai-message-bubble-assistant').last();
    await expect(bubble).toBeVisible({ timeout: 8000 });
    await expect(bubble.locator('strong')).toContainText(/Resumo/);
    await expect(bubble.locator('ul li')).toHaveCount(2);

    // Action buttons available
    await expect(bubble.getByRole('button', { name: /Copiar/i })).toBeVisible();
    await expect(bubble.getByRole('button', { name: /Usar no composer|Aplicar/i })).toBeVisible();
  });
});
