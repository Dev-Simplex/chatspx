// Logged-in smoke for Phase 2 — uses pre-generated dev tokens to inject the
// `cw_d_session_info` cookie, then opens a real conversation and asserts the
// Phase 2 visual cues (collapsed composer, WA header, optional ghost text).
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

if (!SESSION['access-token'] || !SESSION.client || !SESSION.uid) {
  console.error('Missing CW_TOKEN / CW_CLIENT / CW_UID env');
  process.exit(2);
}

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

// 1. Open dashboard via the unassigned conversation list (account 5 has 1500+).
const target = `${BASE}/app/accounts/${ACCOUNT_ID}/custom_view`;
const resp = await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/dashboard`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
const httpStatus = resp ? resp.status() : 'no-response';

// Wait for the conversation list shell to render.
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});

// 2. Click the "Não atribuídas" tab so we get a populated list.
await page.locator('text=Não atribuídas').first().click({ timeout: 8000 }).catch(() => {});
await page.waitForTimeout(2000);

await page.screenshot({ path: '/tmp/phase2_dashboard.png', fullPage: false });

// 3. Navigate directly to a known conversation.
const convDisplayId = process.env.CW_CONV_ID || '1884';
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/${convDisplayId}`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(2500);
const openedConversation = !!(await page.$('.reply-box'));

await page.screenshot({ path: '/tmp/phase2_conversation.png', fullPage: false });

// 4. Validate Phase 2 cues
const replyBox = await page.$('.reply-box');
const hasReplyBox = !!replyBox;
const isCollapsed = !!(await page.$('.reply-box.is-collapsed'));
const hasWaHeader = !!(await page.$('.wa-conversation-header'));
const ghostBefore = !!(await page.$('.wa-ghost-suggestion'));

// Click the editor and confirm it expands (not collapsed)
let isCollapsedAfterFocus = null;
if (hasReplyBox) {
  await page.locator('.reply-box [contenteditable="true"]').first().click().catch(() => {});
  await page.waitForTimeout(500);
  isCollapsedAfterFocus = !!(await page.$('.reply-box.is-collapsed'));
  await page.screenshot({ path: '/tmp/phase2_focused.png', fullPage: false });
}

const result = {
  http_status: httpStatus,
  final_url: page.url(),
  opened_conversation: openedConversation,
  has_reply_box: hasReplyBox,
  collapsed_initial: isCollapsed,
  collapsed_after_focus: isCollapsedAfterFocus,
  has_wa_header: hasWaHeader,
  has_ghost_suggestion: ghostBefore,
  console_errors: errors.slice(0, 5),
  screenshots: ['/tmp/phase2_dashboard.png', '/tmp/phase2_conversation.png', '/tmp/phase2_focused.png'],
};

await browser.close();
writeFileSync('/tmp/phase2_logged.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
process.exit(0);
