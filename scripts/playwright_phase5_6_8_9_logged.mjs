// Phase 5/6/8.1/8.2/9.1/9.4 logged-in smoke
import { chromium } from 'playwright';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = Number(process.env.CW_ACCOUNT_ID || 5);
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

const result = {};

// 1. Open a conversation
await page.goto(
  `${BASE}/app/accounts/${ACCOUNT_ID}/conversations/307`,
  { waitUntil: 'domcontentloaded', timeout: 45000 }
);
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(3000);

result.message_features = {
  has_header: !!(await page.$('.wa-conversation-header')),
  has_contact_presence: !!(await page.$('.wa-contact-presence')),
  has_reaction_trigger: !!(await page.$('.reaction-trigger')),
  has_message_meta_status: !!(await page.$(
    '.i-lucide-check, .i-lucide-check-check'
  )),
};
await page.screenshot({ path: '/tmp/phase5_6_messages.png', fullPage: false });

// 2. Open Copilot drawer
const sparkles = page.locator(
  '.wa-conversation-header .wa-header-icon-btn'
).first();
if ((await sparkles.count()) > 0) {
  await sparkles.click().catch(() => {});
  await page.waitForTimeout(800);
  result.copilot = {
    drawer_open: !!(await page.$('aside.copilot-panel')),
    has_clear_history_btn: !!(await page.$(
      'aside.copilot-panel .i-lucide-trash-2'
    )),
  };
  await page.screenshot({ path: '/tmp/phase7_copilot.png', fullPage: false });
  // Close
  await page
    .locator('aside.copilot-panel button:has(.i-lucide-x)')
    .first()
    .click()
    .catch(() => {});
}

// 3. Density toggle in Settings → General
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/settings/general`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(1500);
result.density = {
  has_compact: !!(await page.$('text=/^Compacto|^Compact/')),
  has_comfortable: !!(await page.$(
    'text=/^Confortável|^Comfortable/'
  )),
  has_spacious: !!(await page.$('text=/^Espaçoso|^Spacious/')),
};

// 4. Mobile viewport — check homepage shows
await page.setViewportSize({ width: 375, height: 812 });
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/dashboard`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2000);
result.mobile = {
  page_renders: !!(await page.$('body')),
  conversation_card_visible: !!(await page.$('.wa-conversation-card')),
};
await page.screenshot({ path: '/tmp/phase9_mobile.png', fullPage: false });

console.log(JSON.stringify({ result, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
