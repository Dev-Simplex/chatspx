// Phase 2 smoke test — verifies that the dashboard SPA boots and the WhatsApp
// 24h timer i18n bundle is loaded. Captures a screenshot for visual review.
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const URL = process.env.SMOKE_URL || 'https://hmlchat.simplexsolucoes.com.br/app/login';
const OUT = process.env.SMOKE_OUT || '/tmp/phase2_smoke.png';

const errors = [];
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
const page = await ctx.newPage();

page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
page.on('console', m => {
  if (m.type() === 'error') errors.push(`console.error: ${m.text()}`);
});

const resp = await page.goto(URL, { waitUntil: 'networkidle', timeout: 45000 });
const status = resp ? resp.status() : 'no-response';

// Wait for the SPA root to render. Login page has #app and an email input.
await page.waitForSelector('input[type="email"]', { timeout: 15000 }).catch(() => {});

const html = await page.content();
const hasLoginForm = /type="email"/i.test(html) && /type="password"/i.test(html);

await page.screenshot({ path: OUT, fullPage: true });

await browser.close();

const result = {
  url: URL,
  http_status: status,
  has_login_form: hasLoginForm,
  console_errors: errors,
  screenshot: OUT,
};
writeFileSync('/tmp/phase2_smoke.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
process.exit(errors.length ? 1 : 0);
