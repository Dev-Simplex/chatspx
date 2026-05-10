// Shared helpers for ChatSPX Copilot E2E specs.
//
// These helpers favour resilience over speed: every selector falls back to a
// data-testid OR an aria-label OR a visible role+name combination, in that
// order. The Copilot UI was authored with i18n keys; helpers therefore prefer
// stable test IDs and aria attributes.
//
// All Captain endpoints are intercepted with `mockCaptain()` so specs never
// depend on a live backend. The fixture-based auth helper signs the agent in
// once via the Devise endpoint and persists the session to disk.

/* eslint-disable no-undef */
const { expect } = require('@playwright/test');

const DEFAULT_TIMEOUT = 8_000;

/**
 * Sign the current Playwright `page` in as an agent using the Devise sign-in
 * endpoint. The session cookie is set on the browser context, so subsequent
 * navigations will be authenticated.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{ email?: string, password?: string }} [creds]
 */
async function loginAsAgent(page, creds = {}) {
  const email = creds.email || process.env.E2E_AGENT_EMAIL || 'agent@chatspx.test';
  const password = creds.password || process.env.E2E_AGENT_PASSWORD || 'Password1!';

  // Try API auth first — fast and stable.
  const response = await page.request.post('/auth/sign_in', {
    data: { email, password },
    headers: { 'Content-Type': 'application/json' },
    failOnStatusCode: false,
  });

  if (!response.ok()) {
    // Fall back to UI-driven sign-in if API auth is disabled in this env.
    await page.goto('/app/login');
    await page.fill('[type="email"]', email);
    await page.fill('[type="password"]', password);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: DEFAULT_TIMEOUT });
    return;
  }

  // Pull the access-token / client headers and seed cookies/storage.
  const headers = response.headers();
  const accessToken = headers['access-token'];
  const client = headers['client'];
  const uid = headers['uid'];
  if (accessToken) {
    await page.context().addCookies([
      { name: 'cw_d_' + Buffer.from(uid).toString('hex').slice(0, 8), value: encodeURIComponent(JSON.stringify({ access_token: accessToken, client, uid })), domain: new URL(page.url() || 'http://localhost').hostname, path: '/' },
    ]);
  }
}

/**
 * Navigate to a conversation. The conversation must exist in the seeded
 * database OR be returned by an intercepted API mock — see `mockConversation`.
 */
async function openConversation(page, conversationId) {
  const accountId = process.env.E2E_ACCOUNT_ID || 1;
  await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}`);
  await page.waitForLoadState('networkidle', { timeout: DEFAULT_TIMEOUT });
}

/**
 * Intercept Captain endpoints. Returns the route handler for cleanup.
 *
 * @param {import('@playwright/test').Page} page
 * @param {object} opts
 * @param {string|RegExp} opts.route — URL pattern (e.g. `**\/captain/responses`)
 * @param {object} [opts.response]   — JSON body to return
 * @param {number} [opts.status]     — HTTP status (default 200)
 * @param {number} [opts.delay]      — ms to delay response (default 0)
 */
async function mockCaptain(page, { route, response = { message: 'mocked reply' }, status = 200, delay = 0 } = {}) {
  await page.route(route, async r => {
    if (delay) {
      await new Promise(res => setTimeout(res, delay));
    }
    await r.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify(response),
    });
  });
}

/**
 * Convenience: stub the Captain "process_event" endpoint with a single
 * deterministic message. Most specs only need this.
 */
async function mockCaptainProcessEvent(page, { message = 'Mock Copilot reply', status = 200, delay = 0 } = {}) {
  await mockCaptain(page, {
    route: /\/api\/v\d+\/accounts\/\d+\/captain\/(tasks|responses|process_event|copilot)/,
    response: { message, status: 'ok' },
    status,
    delay,
  });
}

/**
 * Find the Copilot composer-anchored sparkles button (used by V1 inline menu
 * and V2 panel). Both share the `ai-button` test id.
 */
function sparklesButton(page) {
  return page.getByTestId('ai-button');
}

/**
 * Find the Copilot panel root. Returns null if the panel isn't mounted (V1
 * mode). Useful for `aiV2Flag` mutex assertions.
 */
function panelRoot(page) {
  return page.getByRole('dialog', { name: /copilot/i });
}

/**
 * Open the panel via the conversation header CopilotLauncher button.
 */
async function openPanel(page) {
  await page.getByTestId('copilot-launcher').click();
  await expect(panelRoot(page)).toBeVisible({ timeout: DEFAULT_TIMEOUT });
}

/**
 * Wait for the panel close transition to settle.
 */
async function closePanel(page) {
  await page.keyboard.press('Escape');
  await expect(panelRoot(page)).toBeHidden({ timeout: DEFAULT_TIMEOUT });
}

/**
 * Force a feature flag at the localStorage layer (V2-only override).
 */
async function setFeatureFlag(page, key, value) {
  await page.evaluate(([k, v]) => window.localStorage.setItem(k, v), [key, value]);
}

async function clearFeatureFlag(page, key) {
  await page.evaluate(k => window.localStorage.removeItem(k), key);
}

module.exports = {
  loginAsAgent,
  openConversation,
  mockCaptain,
  mockCaptainProcessEvent,
  sparklesButton,
  panelRoot,
  openPanel,
  closePanel,
  setFeatureFlag,
  clearFeatureFlag,
  DEFAULT_TIMEOUT,
};
