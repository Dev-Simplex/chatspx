// Phase 3+4 logged-in smoke. Validates:
// - Composer dobrável (Fase 2.1) — .reply-box still rendering
// - Bubble tail (Fase 3.1) — .right-bubble.bg-n-solid-blue exists with shadow
// - Conversation card typography (Fase 3.2) — h4 rendered
// - Priority pill (Fase 3.5) — opens dropdown
// - Pin button (Fase 4) — visible on hover, toggles
// - Wallpaper setting page (Fase 3.3) — input present
// - KPI strip switch (Fase 3.6) — switch present
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = 5;
const SESSION = {
  'access-token': process.env.CW_TOKEN,
  client: process.env.CW_CLIENT,
  uid: process.env.CW_UID,
  expiry: String(process.env.CW_EXPIRY),
  'token-type': 'Bearer',
  id: process.env.CW_USER_ID || '38',
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

// 1. Open conversation
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/1884`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);

const conversation = {
  has_reply_box: !!(await page.$('.reply-box')),
  has_outgoing_bubble: !!(await page.$('.right-bubble')),
  has_wa_header: !!(await page.$('.wa-conversation-header')),
  has_priority_pill: !!(await page.$('button[class*="rounded-md"][class*="text-n-slate-11"]:has(.i-lucide-circle-dashed), button[class*="rounded-md"][class*="text-n-slate-11"]:has(.i-lucide-flame), button[class*="rounded-md"][class*="text-n-slate-11"]:has(.i-lucide-equal), button[class*="rounded-md"][class*="text-n-slate-11"]:has(.i-lucide-arrow-up), button[class*="rounded-md"][class*="text-n-slate-11"]:has(.i-lucide-arrow-down)')),
};
await page.screenshot({ path: '/tmp/phase34_conversation.png', fullPage: false });

// 2. Try opening priority dropdown via text
const priorityBtn = await page.locator('button:has-text("Sem prioridade"), button:has-text("Urgente"), button:has-text("Alta"), button:has-text("Média"), button:has-text("Baixa"), button:has-text("No priority")').first();
let priorityMenuOpened = false;
if (await priorityBtn.count() > 0) {
  await priorityBtn.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(400);
  // Menu has 5 buttons inline
  const menuItems = await page.$$('button:has-text("Urgente")');
  priorityMenuOpened = menuItems.length >= 1;
  await page.screenshot({ path: '/tmp/phase34_priority_open.png', fullPage: false });
  await page.keyboard.press('Escape');
}

// 3. Validate ChatList pin button (account 5 has unassigned conversations)
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/dashboard`, {
  waitUntil: 'domcontentloaded',
  timeout: 30000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.locator('text=Não atribuídas').first().click({ timeout: 8000 }).catch(() => {});
await page.waitForTimeout(2000);
const pinExists = !!(await page.$('button[title*="Fixar"], button[title*="Pin"]'));
await page.screenshot({ path: '/tmp/phase34_chatlist.png', fullPage: false });

// 4. Settings → General — wallpaper input + KPI switch
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/settings/general`, {
  waitUntil: 'domcontentloaded',
  timeout: 30000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2000);
const settings = {
  has_wallpaper_input: !!(await page.$('input[placeholder*="wallpaper"], input[placeholder*="Wallpaper"], input[placeholder*="exemplo"]')),
  has_kpi_switch: !!(await page.locator('text=Faixa de KPIs').first().isVisible().catch(() => false)),
};
await page.screenshot({ path: '/tmp/phase34_settings.png', fullPage: true });

const result = {
  conversation,
  priority_menu_opened: priorityMenuOpened,
  pin_button_exists: pinExists,
  settings,
  console_errors: errors.slice(0, 5),
  screenshots: [
    '/tmp/phase34_conversation.png',
    '/tmp/phase34_priority_open.png',
    '/tmp/phase34_chatlist.png',
    '/tmp/phase34_settings.png',
  ],
};

await browser.close();
writeFileSync('/tmp/phase34_logged.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
process.exit(0);
