// Smoke focado no skeleton + performance da galeria (B9)
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.CW_BASE || 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = Number(process.env.CW_ACCOUNT_ID || 5);
const OUT = '/tmp/smoke_2026_04_28';
mkdirSync(OUT, { recursive: true });

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

const consoleMsgs = [];
page.on('console', msg => {
  if (msg.type() === 'warning' || msg.type() === 'error') consoleMsgs.push(`[${msg.type()}] ${msg.text()}`);
});

// Throttle network para garantir skeleton apareça
await page.route('**/api/v1/accounts/*/attachments**', async route => {
  await new Promise(r => setTimeout(r, 500));
  return route.continue();
});

console.log('▶ NAVIGATING TO GALLERY (cold)');
const t0 = Date.now();
const navP = page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/gallery`, {
  waitUntil: 'domcontentloaded',
  timeout: 60000,
});
// Capturar skeleton no instante após o DOM estar pronto, antes da resposta
await page.waitForTimeout(120);
const skeletonInitial = await page.evaluate(() => {
  const node = document.querySelector('[role="status"][aria-busy="true"]');
  const articles = document.querySelectorAll('.grid article');
  return {
    skeletonExists: !!node,
    skeletonAriaLabel: node?.getAttribute('aria-label'),
    articleCount: articles.length,
  };
}).catch(() => ({}));
console.log('Initial state:', skeletonInitial);
await page.screenshot({ path: `${OUT}/B9_01_skeleton.png`, fullPage: false });

await navP;
await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
const tDoneFirst = Date.now() - t0;
const grid = await page.evaluate(() => {
  const articles = document.querySelectorAll('.grid article');
  const styles = articles[0] ? getComputedStyle(articles[0]) : null;
  const imgs = document.querySelectorAll('.grid article img');
  const eagerImgs = Array.from(imgs).filter(i => i.loading === 'eager').length;
  const highPriorityImgs = Array.from(imgs).filter(i => i.fetchPriority === 'high').length;
  return {
    articleCount: articles.length,
    contentVisibility: styles?.contentVisibility,
    containIntrinsicSize: styles?.containIntrinsicSize,
    imagesTotal: imgs.length,
    eagerImgs,
    highPriorityImgs,
  };
});
console.log('Loaded grid:', grid, `(${tDoneFirst}ms)`);
await page.screenshot({ path: `${OUT}/B9_02_loaded.png`, fullPage: false });

// Lighthouse via CDP performance metrics
console.log('▶ Lighthouse-like performance (CDP)');
const cdp = await page.context().newCDPSession(page);
await cdp.send('Performance.enable');

await page.goto('about:blank');
await page.waitForTimeout(500);
const t1 = Date.now();
await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/gallery`, {
  waitUntil: 'domcontentloaded',
  timeout: 60000,
});
await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
const tDoneSecond = Date.now() - t1;

const metrics = await cdp.send('Performance.getMetrics');
const m = Object.fromEntries(metrics.metrics.map(x => [x.name, x.value]));
console.log('CDP metrics (subset):', {
  TaskDuration: m.TaskDuration,
  ScriptDuration: m.ScriptDuration,
  LayoutCount: m.LayoutCount,
  RecalcStyleCount: m.RecalcStyleCount,
  Nodes: m.Nodes,
  JSHeapUsedSize: m.JSHeapUsedSize,
});

// Performance.timing-style: navigation timing
const nav = await page.evaluate(() => {
  const e = performance.getEntriesByType('navigation')[0];
  return e ? {
    domContentLoaded: e.domContentLoadedEventEnd,
    loadEventEnd: e.loadEventEnd,
    fcp: performance.getEntriesByName('first-contentful-paint')[0]?.startTime,
    lcp: performance.getEntriesByName('largest-contentful-paint')[0]?.startTime,
  } : null;
});
const lcpMeasure = await page.evaluate(() => new Promise(resolve => {
  let value = null;
  const po = new PerformanceObserver(list => {
    const entries = list.getEntries();
    value = entries[entries.length - 1]?.startTime;
  });
  try {
    po.observe({ type: 'largest-contentful-paint', buffered: true });
  } catch (e) {
    resolve(null);
    return;
  }
  setTimeout(() => { po.disconnect(); resolve(value); }, 3000);
}));
console.log('Nav metrics:', nav, 'LCP measured:', lcpMeasure);

console.log(`\nFirst load (with skeleton): ${tDoneFirst}ms`);
console.log(`Second load (cache):         ${tDoneSecond}ms`);
console.log('\nConsole errors/warnings related:');
console.log(consoleMsgs.filter(m => m.includes('VoiceCallButton') || m.includes('DateSeparator') || m.includes('Extraneous')).join('\n') || '(none)');

await browser.close();
