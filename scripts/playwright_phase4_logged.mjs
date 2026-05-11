// Phase 4 final logged-in smoke. Validates:
// - Copilot drawer toggle (sparkles button on header)
// - Onboarding checklist visible at bottom-right
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = Number(process.env.CW_ACCOUNT_ID || 1);
const SESSION = {
  'access-token': process.env.CW_TOKEN,
  client: process.env.CW_CLIENT,
  uid: process.env.CW_UID,
  expiry: String(process.env.CW_EXPIRY),
  'token-type': 'Bearer',
  id: process.env.CW_USER_ID || '1',
};

const errors = [];
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  ignoreHTTPSErrors: true,
  viewport: { width: 1440, height: 900 },
});
await ctx.addCookies([
  {
    name: 'cw_d_session_info',
    value: encodeURIComponent(JSON.stringify(SESSION)),
    domain: 'hmlchat.simplexsolucoes.com.br',
    path: '/',
    sameSite: 'Lax',
  },
]);
const page = await ctx.newPage();
page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
page.on('console', m => {
  if (m.type() === 'error') errors.push(`console.error: ${m.text()}`);
});

// 1. Dashboard for onboarding visibility
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/dashboard`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);

const onboarding = {
  has_rocket_icon: !!(await page.$('.i-lucide-rocket')),
  has_onboarding_widget: !!(await page.$('text=/Comece por aqui|Get started/')),
};
await page.screenshot({ path: '/tmp/phase4_onboarding.png', fullPage: false });

// 2. Open a conversation and toggle Copilot - use direct URL
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/1884`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(3000);

let copilotOpened = false;
let copilotClosed = false;
let sparklesVisible = false;
let headerExists = !!(await page.$('.wa-conversation-header'));

if (headerExists) {
  // Sparkles button is the FIRST wa-header-icon-btn in the right side actions
  const headerButtons = await page.$$('.wa-conversation-header .wa-header-icon-btn');
  sparklesVisible = headerButtons.length >= 2;
  const sparklesBtn = page.locator('.wa-conversation-header .wa-header-icon-btn').first();

  if (await sparklesBtn.count() > 0) {
    await sparklesBtn.click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(500);
    copilotOpened = !!(await page.$('aside.copilot-panel'));
    await page.screenshot({ path: '/tmp/phase4_copilot_open.png', fullPage: false });

    // Close
    const closeBtn = page.locator('aside.copilot-panel button:has(.i-lucide-x)').first();
    if (await closeBtn.count() > 0) {
      await closeBtn.click({ timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(400);
      copilotClosed = !(await page.$('aside.copilot-panel'));
    }
  }
}

const result = {
  onboarding,
  copilot: {
    header_exists: headerExists,
    sparkles_visible: sparklesVisible,
    opened: copilotOpened,
    closed: copilotClosed,
  },
  console_errors: errors.slice(0, 8),
  screenshots: ['/tmp/phase4_onboarding.png', '/tmp/phase4_copilot_open.png'],
};

await browser.close();
writeFileSync('/tmp/phase4_logged.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
process.exit(0);
