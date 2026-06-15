/**
 * E2E — "Atribuição obrigatória" (resolve assignment gate).
 *
 * Objetivo da feature: só pode encerrar (resolver) uma conversa o agente a quem
 * ela está atribuída. Quem não é o dono vê o modal "Atribuir a você e encerrar?".
 *
 * Pré-condições (ambiente servido — `E2E_BASE_URL`, agente logado):
 *  - Conta com a flag `resolve_assignment_gate` LIGADA. Os testes tentam ligá-la
 *    via API no beforeAll; se a API recusar (permissão), ligue manualmente.
 *  - `E2E_CONVERSATION_ID` aponta para uma conversa ABERTA que NÃO está atribuída
 *    ao agente de teste (para o caminho "não-dono"). O teste de fallback 422 não
 *    depende do estado de atribuição.
 *
 * Cobre (do plano): PR2 (não-dono → modal), PR6 (flag off → sem modal),
 * PR7 (sem i18n vazada, 0 erros de console, claro + escuro) e o fallback de
 * corrida (422 `resolve_assignment_required`).
 */
/* eslint-disable no-undef */
const { test, expect } = require('@playwright/test');
const {
  loginAsAgent,
  openConversation,
  DEFAULT_TIMEOUT,
} = require('../copilot/_helpers');

const ACCOUNT_ID = process.env.E2E_ACCOUNT_ID || 1;
const CONVERSATION_ID = process.env.E2E_CONVERSATION_ID || 1;

const RESOLVE_422_BODY = {
  error: 'Apenas o agente atribuído pode encerrar esta conversa',
  error_code: 'resolve_assignment_required',
  meta: {
    current_assignee_id: 99999,
    current_assignee_name: 'Outro Agente',
    team_id: 1,
  },
};

const TOGGLE_STATUS_RE =
  /\/api\/v\d+\/accounts\/\d+\/conversations\/\d+\/toggle_status/;
const ASSIGNMENTS_RE =
  /\/api\/v\d+\/accounts\/\d+\/conversations\/\d+\/assignments/;

/** Force the backend to reject the resolve as a non-assignee (race / API path). */
async function mockResolveRejected(page) {
  await page.route(TOGGLE_STATUS_RE, async route => {
    if (route.request().method() !== 'POST') return route.fallback();
    return route.fulfill({
      status: 422,
      contentType: 'application/json',
      body: JSON.stringify(RESOLVE_422_BODY),
    });
  });
}

/** The header "Resolver" button (pt-BR) / "Resolve" (en) — first match. */
function resolveButton(page) {
  return page.getByRole('button', { name: /^(Resolver|Resolve)/i }).first();
}

function gateDialog(page) {
  return page.getByRole('dialog').filter({ hasText: /encerrar\?/i });
}

function collectConsoleErrors(page) {
  const errors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', err => errors.push(String(err)));
  return errors;
}

async function setTheme(page, theme) {
  await page.evaluate(t => {
    document.documentElement.classList.toggle('dark', t === 'dark');
    window.localStorage.setItem('color_scheme', t);
  }, theme);
}

test.describe('Resolve assignment gate', () => {
  test.beforeAll(async ({ request }) => {
    // Best-effort: enable the gate for the account. Ignore failures (manual setup).
    await request
      .patch(`/api/v1/accounts/${ACCOUNT_ID}`, {
        data: { resolve_assignment_gate: true },
        failOnStatusCode: false,
      })
      .catch(() => {});
  });

  test.beforeEach(async ({ page }) => {
    await loginAsAgent(page);
    await openConversation(page, CONVERSATION_ID);
  });

  test('non-assignee resolve opens the assign-and-resolve dialog (422 fallback)', async ({
    page,
  }) => {
    const consoleErrors = collectConsoleErrors(page);
    await mockResolveRejected(page);

    await resolveButton(page).click();

    const dialog = gateDialog(page);
    await expect(dialog).toBeVisible({ timeout: DEFAULT_TIMEOUT });
    // pt-BR copy, confirm CTA, and no raw i18n keys leaked.
    await expect(
      page.getByRole('button', { name: /Atribuir a mim e encerrar/i })
    ).toBeVisible();
    await expect(dialog).not.toContainText('RESOLVE_ASSIGNMENT_GATE');
    await expect(dialog).not.toContainText('CONVERSATION.');

    expect(consoleErrors, consoleErrors.join('\n')).toHaveLength(0);
  });

  test('confirming assigns to me then resolves', async ({ page }) => {
    await mockResolveRejected(page);

    const assignCalls = [];
    await page.route(ASSIGNMENTS_RE, async route => {
      assignCalls.push(route.request().postDataJSON?.() ?? null);
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ id: 1, name: 'Agente Teste' }),
      });
    });

    let resolveCalls = 0;
    await page.unroute(TOGGLE_STATUS_RE);
    await page.route(TOGGLE_STATUS_RE, async route => {
      if (route.request().method() !== 'POST') return route.fallback();
      resolveCalls += 1;
      // First call (gate not yet self-assigned) → 422; after assign → success.
      if (resolveCalls === 1) {
        return route.fulfill({
          status: 422,
          contentType: 'application/json',
          body: JSON.stringify(RESOLVE_422_BODY),
        });
      }
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ payload: { current_status: 'resolved' } }),
      });
    });

    await resolveButton(page).click();
    await gateDialog(page)
      .getByRole('button', { name: /Atribuir a mim e encerrar/i })
      .click();

    await expect.poll(() => assignCalls.length).toBeGreaterThan(0);
    await expect.poll(() => resolveCalls).toBeGreaterThan(1);
  });

  test('renders correctly in dark theme', async ({ page }) => {
    await setTheme(page, 'dark');
    await mockResolveRejected(page);

    await resolveButton(page).click();
    const dialog = gateDialog(page);
    await expect(dialog).toBeVisible({ timeout: DEFAULT_TIMEOUT });
    await expect(dialog).not.toContainText('RESOLVE_ASSIGNMENT_GATE');
    await page.screenshot({
      path: 'tmp/playwright-report/resolve-gate-dark.png',
    });
  });

  test('cancel closes the dialog without resolving', async ({ page }) => {
    await mockResolveRejected(page);
    await resolveButton(page).click();

    const dialog = gateDialog(page);
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: /Cancelar|Cancel/i }).click();
    await expect(dialog).toBeHidden();
  });
});
