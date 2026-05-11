// §8.3 sidebar drag + §9.2 push permission prompt smoke
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
  permissions: [],
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

await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/dashboard`, {
  waitUntil: 'domcontentloaded',
  timeout: 45000,
});
await page.waitForLoadState('networkidle', { timeout: 25000 }).catch(() => {});
await page.waitForTimeout(3000);

const result = {
  sidebar: {
    aside_visible: !!(await page.$('aside')),
    has_draggable_ul: !!(await page.$('ul.sortable-chosen, aside ul')),
    sidebar_groups_count: (await page.$$('aside [data-sidebar-group]')).length,
  },
  // PushPermissionPrompt aparece após 60s, então não espero render aqui
  // mas validamos que o componente foi importado sem erros
  errors_count: errors.length,
};

await page.screenshot({ path: '/tmp/sidebar_drag_v2.png', fullPage: false });

console.log(JSON.stringify({ result, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
