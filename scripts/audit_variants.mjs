// Capturar variants de bubble para validar consistência hover
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = 5;
const OUT = '/tmp/visual_audit_v2';
mkdirSync(OUT, { recursive: true });

const SESSION = {
  'access-token': '97KWHzkiKRxjp2ZFBAZfuQ',
  client: 'JH61CTOTPdIfbHwqBSP2kQ',
  uid: 'sup@simplexsolucoes.com.br',
  expiry: '1782680038',
  'token-type': 'Bearer',
  id: '1',
};

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  ignoreHTTPSErrors: true,
  viewport: { width: 1600, height: 1100 },
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

// Conv 46 — agente + cliente (cor azul/slate)
// Conv 422 — tem mensagem private (cor amber)
const targets = [
  { id: 46, name: 'agent_user_variants' },
  { id: 422, name: 'private_variant' },
];

for (const t of targets) {
  console.log(`▶ ${t.name} (conv ${t.id})`);
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/${t.id}`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(4500);

  // Capturar variants no DOM
  const variants = await page.evaluate(() => {
    const bubbles = document.querySelectorAll('.message-bubble-container');
    return Array.from(bubbles).map(c => {
      const inner = c.querySelector('[class*="bg-n-solid"], [class*="bg-n-slate-4"], [class*="bg-n-solid-amber"]');
      const bg = inner ? getComputedStyle(inner).backgroundColor : null;
      const id = c.getAttribute('data-message-id');
      return {
        id,
        isOutgoing: c.className.includes('justify-end'),
        bg,
        clsSnippet: inner?.className.slice(0, 80),
      };
    });
  });
  console.log(`Variants encontradas:`, JSON.stringify(variants.slice(0, 5), null, 2));

  // Screenshot full + crop dos bubbles
  await page.screenshot({ path: `${OUT}/variant_${t.name}.png`, fullPage: false });

  // Hover na primeira bubble
  const firstBubble = page.locator('.message-bubble-container').first();
  if ((await firstBubble.count()) > 0) {
    await firstBubble.hover();
    await page.waitForTimeout(500);
    const box = await firstBubble.boundingBox();
    if (box) {
      await page.screenshot({
        path: `${OUT}/hover_${t.name}.png`,
        clip: {
          x: Math.max(0, box.x - 20),
          y: Math.max(0, box.y - 10),
          width: Math.min(800, box.width + 40),
          height: Math.min(150, box.height + 20),
        }
      });
    }
  }
}

await browser.close();
console.log('Done');
