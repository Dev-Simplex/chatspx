import { chromium } from 'playwright';
const SESSION = {
  'access-token': 'UEUwg8xwayv4t-B7Kl91Pg',
  client: 'C1pzyQ7pCwhc5duyH4KfMQ',
  uid: 'dev@simplexsolucoes.com.br',
  expiry: '1777426629',
  'token-type': 'Bearer',
  id: '38',
};
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } });
await ctx.addCookies([{ name: 'cw_d_session_info', value: encodeURIComponent(JSON.stringify(SESSION)), domain: 'hmlchat.simplexsolucoes.com.br', path: '/', sameSite: 'Lax' }]);
const page = await ctx.newPage();
// Hit dashboard, click "Não atribuídas" tab — same flow that worked in phase34_logged.mjs
await page.goto('https://hmlchat.simplexsolucoes.com.br/app/accounts/5/dashboard', { waitUntil: 'domcontentloaded' });
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(()=>{});
await page.locator('text=Não atribuídas').first().click({ timeout: 10000 }).catch(()=>{});
await page.waitForTimeout(4000);

const html = await page.content();
const hasPinFixar = html.includes('Fixar conversa');
const hasPinIcon = html.includes('i-lucide-pin');
const totalCards = await page.locator('.wa-conversation-card').count();

if (totalCards > 0) {
  const firstCard = page.locator('.wa-conversation-card').first();
  await firstCard.hover().catch(()=>{});
  await page.waitForTimeout(800);
  await page.screenshot({ path: '/tmp/phase4_pin_hover.png', fullPage: false, clip: { x: 70, y: 165, width: 380, height: 100 } });
  // Click pin
  await page.locator('.wa-conversation-card').first().locator('button[title*="Fixar"]').click({ force: true, timeout: 5000 }).catch(()=>{});
  await page.waitForTimeout(800);
}
const pinnedCount = await page.locator('.wa-conversation-card--pinned').count();

console.log(JSON.stringify({ totalCards, hasPinFixar, hasPinIcon, pinnedCount }));
await browser.close();
