// Smoke test final — valida B1..B9 do plano de fixes UI 2026-04-28
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'node:fs';

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
  if (msg.type() === 'warning' || msg.type() === 'error') {
    consoleMsgs.push(`[${msg.type()}] ${msg.text()}`);
  }
});

const result = { steps: [], console: { warnings: 0, errors: 0, voiceCallButton: 0, dateSeparator: 0 } };

async function step(name, fn) {
  console.log(`▶ ${name}`);
  try {
    const r = await fn();
    result.steps.push({ name, ok: true, ...r });
    console.log(`✅ ${name}`);
  } catch (e) {
    result.steps.push({ name, ok: false, error: e.message });
    console.log(`❌ ${name}: ${e.message}`);
  }
}

// 1) Conversa — bubble hover (B3, B4, B8)
await step('conversation_load', async () => {
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/307`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3500);
  await page.screenshot({ path: `${OUT}/01_conversation_loaded.png`, fullPage: false });
  return { url: page.url() };
});

// B5 — header sem sparkle
await step('B5_header_sparkle_removed', async () => {
  const sparkleInHeader = await page.evaluate(() => {
    const header = document.querySelector('.conversation--header, [class*="header"]');
    if (!header) return null;
    return {
      sparkleCount: header.querySelectorAll('.i-lucide-sparkles').length,
    };
  });
  await page.screenshot({ path: `${OUT}/02_B5_header.png`, clip: { x: 0, y: 0, width: 1440, height: 80 } });
  return sparkleInHeader;
});

// B3 + B4 — hover bubble revela star + picker
await step('B3_B4_bubble_hover', async () => {
  const bubbles = page.locator('.group\\/bubble');
  const count = await bubbles.count();
  if (count === 0) throw new Error('Nenhum bubble encontrado');
  await bubbles.first().hover();
  await page.waitForTimeout(800);
  const visibility = await bubbles.first().evaluate(el => {
    const star = el.querySelector('button[title*="vorit"], button[title*="ar mensagem"], button[title*="emover"]');
    const picker = el.querySelector('button.reaction-trigger');
    const starBox = star ? star.getBoundingClientRect() : null;
    const bubbleBox = el.getBoundingClientRect();
    return {
      bubbleCount: 1,
      hasStar: !!star,
      hasPicker: !!picker,
      starOpacity: star ? getComputedStyle(star.parentElement || star).opacity : null,
      pickerOpacity: picker ? getComputedStyle(picker.parentElement || picker).opacity : null,
      starInsideBubble: starBox && bubbleBox
        ? starBox.left >= bubbleBox.left - 2 && starBox.right <= bubbleBox.right + 2
        : null,
    };
  });
  await page.screenshot({ path: `${OUT}/03_B3_B4_bubble_hover.png`, fullPage: false });
  return { totalBubbles: count, ...visibility };
});

// B6 — reply box sem banner
await step('B6_reply_box_no_banner', async () => {
  const txt = await page.evaluate(() => {
    const replyBox = document.querySelector('.message-reply-box, .reply-box, .conv-reply-box, footer');
    if (!replyBox) return { found: false };
    const html = replyBox.innerHTML.toLowerCase();
    return {
      found: true,
      hasBannerText: html.includes('signature') || html.includes('assinatura não está') || html.includes('não está configurada'),
    };
  });
  return txt;
});

// B1 — toggle do contact panel + B2 — VoiceCallButton renderiza
await step('B1_B2_contact_panel_toggle', async () => {
  // Clicar botão flutuante de toggle
  const toggle = page.locator('[data-testid="conversation-sidebar-contact-toggle"]');
  const initiallyVisible = await toggle.isVisible().catch(() => false);
  await page.screenshot({ path: `${OUT}/04_B1_panel_open.png`, fullPage: false });
  if (!initiallyVisible) throw new Error('Toggle não está visível');
  await toggle.click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${OUT}/05_B1_panel_closed.png`, fullPage: false });
  await toggle.click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${OUT}/06_B1_panel_open_again.png`, fullPage: false });

  // Verificar VoiceCallButton renderizou
  const voiceCallExists = await page.evaluate(() => {
    const els = document.querySelectorAll('voicecallbutton, [class*="VoiceCall"]');
    return Array.from(els).map(e => ({ tag: e.tagName, html: (e.innerHTML || '').slice(0, 80) }));
  });
  // Phone icon dentro do contact panel
  const phoneIcon = await page.locator('.conversation--details, [class*="contact-info"]')
    .first()
    .locator('.i-lucide-phone, [class*="phone"]')
    .count()
    .catch(() => 0);
  return { initiallyVisible, voiceCallElements: voiceCallExists, phoneIcons: phoneIcon };
});

// B7 — DateSeparator console — verificar via console capturas
await step('B2_B7_console_warnings', async () => {
  const vcb = consoleMsgs.filter(m => m.includes('VoiceCallButton')).length;
  const ds = consoleMsgs.filter(m => m.includes('DateSeparator') || m.includes('Invalid prop')).length;
  result.console.voiceCallButton = vcb;
  result.console.dateSeparator = ds;
  result.console.errors = consoleMsgs.filter(m => m.startsWith('[error]')).length;
  result.console.warnings = consoleMsgs.filter(m => m.startsWith('[warning]')).length;
  return { vcb, ds, totalErrors: result.console.errors, totalWarnings: result.console.warnings };
});

// B9 — Galeria
await step('B9_gallery_skeleton_then_content', async () => {
  // Limpar console msgs anteriores para gallery
  consoleMsgs.length = 0;
  const t0 = Date.now();
  const navP = page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/gallery`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  // Tentar capturar skeleton ANTES do conteúdo
  await page.waitForTimeout(150);
  const skeletonSnap = await page.evaluate(() => {
    const node = document.querySelector('[role="status"][aria-busy="true"]');
    return {
      exists: !!node,
      ariaLabel: node?.getAttribute('aria-label') || null,
      role: node?.getAttribute('role') || null,
    };
  }).catch(() => ({ exists: false }));
  await page.screenshot({ path: `${OUT}/07_B9_gallery_skeleton.png`, fullPage: false });

  await navP;
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  const t1 = Date.now();
  const grid = await page.evaluate(() => {
    const articles = document.querySelectorAll('.grid article');
    const first = articles[0];
    const styles = first ? getComputedStyle(first) : null;
    return {
      cardCount: articles.length,
      firstCardContentVisibility: styles?.contentVisibility || styles?.['content-visibility'] || null,
      firstCardWidth: first ? first.getBoundingClientRect().width : null,
    };
  });
  await page.screenshot({ path: `${OUT}/08_B9_gallery_loaded.png`, fullPage: false });
  return { skeleton: skeletonSnap, grid, paintMs: t1 - t0 };
});

// Backend timing — request /api/v1/accounts/{id}/attachments
await step('B9_backend_timing', async () => {
  const t0 = Date.now();
  const resp = await page.request.get(
    `${BASE}/api/v1/accounts/${ACCOUNT_ID}/attachments?type=image,video,ig_reel&page=1`,
    {
      headers: {
        'access-token': SESSION['access-token'],
        client: SESSION.client,
        uid: SESSION.uid,
        expiry: SESSION.expiry,
        'Content-Type': 'application/json',
      },
    }
  );
  const t1 = Date.now();
  const body = await resp.json().catch(() => null);
  return {
    status: resp.status(),
    timeMs: t1 - t0,
    cacheControl: resp.headers()['cache-control'],
    payloadCount: body?.payload?.length || 0,
    totalCount: body?.meta?.total_count || 0,
  };
});

// Re-fazer mesma request — deve cair em cache (Rails.cache)
await step('B9_backend_timing_cached', async () => {
  const t0 = Date.now();
  const resp = await page.request.get(
    `${BASE}/api/v1/accounts/${ACCOUNT_ID}/attachments?type=image,video,ig_reel&page=1`,
    {
      headers: {
        'access-token': SESSION['access-token'],
        client: SESSION.client,
        uid: SESSION.uid,
        expiry: SESSION.expiry,
        'Content-Type': 'application/json',
      },
    }
  );
  const t1 = Date.now();
  return { status: resp.status(), timeMs: t1 - t0 };
});

// Final
result.consoleMessages = consoleMsgs.slice(-50);
writeFileSync(`${OUT}/result.json`, JSON.stringify(result, null, 2));
console.log('\n=== SUMMARY ===');
console.log(JSON.stringify(result, null, 2));

await browser.close();
process.exit(result.steps.every(s => s.ok) ? 0 : 1);
