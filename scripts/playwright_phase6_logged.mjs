// Phase 6 (ajustes §6) logged-in smoke:
// - §6.1+§6.2+§6.5: Settings → Integrações → OpenAI (key input + 2 model selects)
// - §6.3: Settings → Inboxes → [first] → Configuration → pin_mode radio
// - §6.4: Settings → Account → ChatWallpaper tabs (URL/Upload)
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

// 1. OpenAI integration page
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/settings/integrations/openai`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(1500);

result.openai_page = {
  has_password_input: !!(await page.$('input[type=password]')),
  has_test_key_button: !!(await page.$('button:has-text("Testar")')),
  has_save_button: !!(await page.$('button:has-text("Salvar")')),
  selects_count: (await page.$$('select')).length,
};
await page.screenshot({ path: '/tmp/phase6_openai_settings.png', fullPage: true });

// 2. Inbox configuration page (pin_mode radio) — direct URL
const INBOX_ID = Number(process.env.CW_INBOX_ID || 8);
await page.goto(
  `${BASE}/app/accounts/${ACCOUNT_ID}/settings/inboxes/${INBOX_ID}/configuration`,
  {
    waitUntil: 'domcontentloaded',
    timeout: 45000,
  }
);
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);
result.inbox_config = {
  has_pin_mode_per_agent: !!(await page.$(
    'input[type=radio][value=per_agent]'
  )),
  has_pin_mode_per_inbox: !!(await page.$(
    'input[type=radio][value=per_inbox]'
  )),
  has_pin_mode_title: !!(await page.$(
    'text=/Conversas fixadas|Pinned conversations/'
  )),
};
await page.screenshot({
  path: '/tmp/phase6_inbox_pin_mode.png',
  fullPage: true,
});

// 3. ChatWallpaper tabs in Account → General
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/settings/general`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2000);

result.wallpaper = {
  has_url_tab: !!(await page.$('text=/^URL externa|^External URL/')),
  has_upload_tab: !!(await page.$('text=/^Upload$/')),
  has_url_input: !!(await page.$('input[type=url]')),
};
await page.screenshot({ path: '/tmp/phase6_wallpaper.png', fullPage: true });

console.log(JSON.stringify({ result, errors }, null, 2));
await browser.close();
