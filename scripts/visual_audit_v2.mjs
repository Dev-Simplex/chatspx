// Audit v2 — focado nas mudanças de hoje
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'node:fs';

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
const consoleMsgs = [];
page.on('console', msg => {
  if (msg.type() === 'warning' || msg.type() === 'error') {
    consoleMsgs.push(`[${msg.type()}] ${msg.text().slice(0, 250)}`);
  }
});

const audit = { steps: [] };
async function step(name, fn) {
  console.log(`▶ ${name}`);
  try {
    const r = (await fn()) || {};
    audit.steps.push({ name, ok: true, ...r });
    console.log(`✅ ${name}`);
  } catch (e) {
    audit.steps.push({ name, ok: false, error: e.message });
    console.log(`❌ ${name}: ${e.message}`);
  }
}

// Conversa 308 tem 44 mensagens incoming + 1 outgoing — bom mix pra testar avatar
const pickedConvId = process.env.CONV_ID || '308';

await step('LOAD_CONVERSATION', async () => {
  const cid = pickedConvId;
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/${cid}`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3500);
  await page.screenshot({ path: `${OUT}/01_conversation.png`, fullPage: false });
  return { convId: cid };
});

// ============ Avatar nos bubbles ============
await step('AVATAR_CHECK', async () => {
  const data = await page.evaluate(() => {
    const grids = document.querySelectorAll('[style*="grid-template-areas"]');
    let leftWithAvatar = 0;
    let rightWithAvatar = 0;
    let leftWithoutAvatar = 0;
    grids.forEach(g => {
      const style = g.getAttribute('style') || '';
      const hasAvatarSlot = !!g.querySelector('[class*="grid-area:avatar"]');
      if (style.includes('"avatar bubble"')) {
        if (hasAvatarSlot) leftWithAvatar++;
        else leftWithoutAvatar++;
      } else if (style.includes('"bubble avatar"')) {
        if (hasAvatarSlot) rightWithAvatar++;
      }
    });
    return { totalGrids: grids.length, leftWithAvatar, leftWithoutAvatar, rightWithAvatar };
  });
  return data;
});

// ============ Crop bubble incoming ============
await step('CROP_INCOMING_BUBBLE', async () => {
  const incomingBubble = await page.evaluateHandle(() => {
    const grids = Array.from(document.querySelectorAll('[style*="grid-template-areas"]'));
    return grids.find(g => (g.getAttribute('style') || '').includes('"avatar bubble"'));
  });
  const el = incomingBubble.asElement();
  if (el) {
    await el.scrollIntoViewIfNeeded();
    await page.waitForTimeout(400);
    await el.screenshot({ path: `${OUT}/02_incoming_with_avatar.png` });
  }
  return { found: !!el };
});

// ============ Crop bubble outgoing ============
await step('CROP_OUTGOING_BUBBLE', async () => {
  const outgoingBubble = await page.evaluateHandle(() => {
    const grids = Array.from(document.querySelectorAll('[style*="grid-template-areas"]'));
    return grids.find(g => (g.getAttribute('style') || '').includes('"bubble avatar"'));
  });
  const el = outgoingBubble.asElement();
  if (el) {
    await el.scrollIntoViewIfNeeded();
    await page.waitForTimeout(400);
    await el.screenshot({ path: `${OUT}/03_outgoing_with_avatar.png` });
  }
  return { found: !!el };
});

// ============ Right-click context menu ============
await step('RIGHT_CLICK_MENU', async () => {
  // Encontrar um bubble texto (não imagem)
  const bubble = await page.evaluateHandle(() => {
    const bubbles = Array.from(document.querySelectorAll('[data-bubble-name="text"]'));
    return bubbles[bubbles.length - 1] || null;
  });
  const el = bubble.asElement();
  if (!el) throw new Error('no text bubble found');
  await el.scrollIntoViewIfNeeded();
  await page.waitForTimeout(400);
  await el.click({ button: 'right' });
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${OUT}/04_contextmenu.png`, fullPage: false });
  const items = await page.evaluate(() => {
    const menu = document.querySelector('.context-menu, [class*="context-menu"], .menu-container');
    if (!menu) return [];
    const list = menu.querySelectorAll('button, [role="menuitem"], li, .menu-item');
    return Array.from(list).map(i => i.textContent?.trim().split('\n')[0]).filter(Boolean);
  });
  await page.keyboard.press('Escape');
  return { items, hasFavoritar: items.some(t => /favorit/i.test(t)) };
});

// ============ No reactions remnants ============
await step('NO_REACTIONS_NO_STAR_TOGGLE', async () => {
  return await page.evaluate(() => ({
    reactionTriggers: document.querySelectorAll('.reaction-trigger').length,
    reactionChips: document.querySelectorAll('.reaction-chip').length,
    floatingStarButtons: Array.from(
      document.querySelectorAll('button[title*="vorit"]')
    ).filter(b => getComputedStyle(b.parentElement || b).position === 'absolute').length,
  }));
});

// ============ Header sem sparkle ============
await step('HEADER', async () => {
  const data = await page.evaluate(() => {
    const headers = document.querySelectorAll('header, [class*="header"]');
    let totalSparkles = 0;
    headers.forEach(h => {
      totalSparkles += h.querySelectorAll('.i-lucide-sparkles').length;
    });
    return { totalSparkles, headerCount: headers.length };
  });
  // Crop só do conversation header
  const headerEl = await page.$('.conversation--header');
  if (headerEl) await headerEl.screenshot({ path: `${OUT}/05_header.png` });
  return data;
});

// ============ Reply box sem banner ============
await step('REPLY_BOX', async () => {
  const data = await page.evaluate(() => {
    const replyBox = document.querySelector('[class*="reply-box"], footer, .conv-reply-box');
    if (!replyBox) return { found: false };
    const html = replyBox.innerHTML.toLowerCase();
    return {
      found: true,
      hasSignatureBanner: html.includes('configurada') || html.includes('signature') || html.includes('assinatura não'),
    };
  });
  return data;
});

// ============ Console final ============
audit.console = {
  totalErrors: consoleMsgs.filter(m => m.startsWith('[error]')).length,
  totalWarnings: consoleMsgs.filter(m => m.startsWith('[warning]')).length,
  voiceCallButton: consoleMsgs.filter(m => m.includes('VoiceCallButton')).length,
  dateSeparator: consoleMsgs.filter(m => m.includes('DateSeparator')).length,
  fragmentRoot: consoleMsgs.filter(m => m.includes('Extraneous')).length,
  unknownComponent: consoleMsgs.filter(m => m.includes('Failed to resolve')).length,
  vueWarn: consoleMsgs.filter(m => m.includes('[Vue warn]')).length,
  uniqueMessages: [...new Set(consoleMsgs)].slice(-15),
};

writeFileSync(`${OUT}/audit.json`, JSON.stringify(audit, null, 2));
console.log('\n=== AUDIT ===');
console.log(JSON.stringify(audit, null, 2));
await browser.close();
