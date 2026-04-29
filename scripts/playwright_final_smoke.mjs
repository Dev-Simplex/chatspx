// Final smoke test — validate critical surfaces
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

const result = {};

// 1. Settings → General — wallpaper tabs + density toggle + KPI strip
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/settings/general`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);
const densityButtons = await page.$$eval('button', btns =>
  btns.map(b => b.textContent?.trim()).filter(Boolean)
);
result.general_settings = {
  has_wallpaper_url_tab: densityButtons.includes('URL externa'),
  has_wallpaper_upload_tab: densityButtons.includes('Upload'),
  has_density_compact: densityButtons.includes('Compacto'),
  has_density_comfortable: densityButtons.includes('Confortável'),
  has_density_spacious: densityButtons.includes('Espaçoso'),
};
await page.screenshot({ path: '/tmp/final_general.png', fullPage: true });

// 2. Conversation 307 — message bubble with reactions trigger
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/307`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(3500);
result.conversation = {
  reaction_triggers: (await page.$$('.reaction-trigger')).length,
  message_status_icons: (
    await page.$$('.i-lucide-check, .i-lucide-check-check')
  ).length,
  contact_name: !!(await page.$('.wa-contact-name')),
  star_buttons: (await page.$$('button[title*="vorit"]')).length,
};
// Hover on first message to make star button visible
const firstBubble = page.locator('.message-bubble-container').first();
if ((await firstBubble.count()) > 0) {
  await firstBubble.hover().catch(() => {});
  await page.waitForTimeout(500);
}
await page.screenshot({
  path: '/tmp/final_conversation.png',
  fullPage: false,
});

// 3. Inbox config — pin mode
await page.goto(
  `${BASE}/app/accounts/${ACCOUNT_ID}/settings/inboxes/8/configuration`,
  { waitUntil: 'domcontentloaded', timeout: 45000 }
);
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);
result.inbox_config = {
  pin_mode_radios: (
    await page.$$('input[type=radio][value=per_agent], input[type=radio][value=per_inbox]')
  ).length,
};
await page.screenshot({
  path: '/tmp/final_inbox_pin_mode.png',
  fullPage: true,
});

// 4. OpenAI integration page
await page.goto(
  `${BASE}/app/accounts/${ACCOUNT_ID}/settings/integrations/openai`,
  { waitUntil: 'domcontentloaded', timeout: 45000 }
);
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(1500);
result.openai_settings = {
  password_input: !!(await page.$('input[type=password]')),
  selects: (await page.$$('select')).length,
};
await page.screenshot({
  path: '/tmp/final_openai_settings.png',
  fullPage: true,
});

console.log(JSON.stringify(result, null, 2));
await browser.close();
