import { chromium } from 'playwright';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = 5;
const SESSION = {
  'access-token': process.env.CW_TOKEN,
  client: process.env.CW_CLIENT,
  uid: process.env.CW_UID,
  expiry: String(process.env.CW_EXPIRY),
  'token-type': 'Bearer',
  id: process.env.CW_USER_ID || '1',
};

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } });
await ctx.addCookies([
  { name: 'cw_d_session_info', value: encodeURIComponent(JSON.stringify(SESSION)), domain: 'hmlchat.simplexsolucoes.com.br', path: '/', sameSite: 'Lax' },
]);
const page = await ctx.newPage();
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/1884`, { waitUntil: 'domcontentloaded', timeout: 45000 });
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(3000);

const headerHTML = await page.$eval('.wa-conversation-header', el => el.outerHTML).catch(() => 'NO_HEADER');
console.log('---HEADER HTML---');
console.log(headerHTML.slice(0, 4000));

const sparklesAlt = await page.$$eval('[class*="sparkle"]', els => els.map(e => ({ class: e.className, tag: e.tagName })));
console.log('---SPARKLES MATCHES---');
console.log(JSON.stringify(sparklesAlt, null, 2));

await browser.close();
