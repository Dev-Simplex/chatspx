// Varredura visual completa após mudanças avatar/star/reactions
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'node:fs';

const BASE = 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = 5;
const OUT = '/tmp/visual_audit_2026_04_29';
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
    consoleMsgs.push(`[${msg.type()}] ${msg.text().slice(0, 200)}`);
  }
});

const audit = { steps: [], issues: [] };

async function shoot(name, fn) {
  console.log(`▶ ${name}`);
  try {
    const result = await fn();
    audit.steps.push({ name, ok: true, ...result });
    console.log(`✅ ${name}`);
  } catch (e) {
    audit.steps.push({ name, ok: false, error: e.message });
    console.log(`❌ ${name}: ${e.message}`);
  }
}

// ============ 1. Conversa — bubble incoming com avatar ============
await shoot('A1_conversation_load', async () => {
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/307`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3500);
  await page.screenshot({ path: `${OUT}/A1_conversation.png`, fullPage: false });
  return { url: page.url() };
});

// ============ 2. Avatar nos bubbles incoming + outgoing ============
await shoot('A2_bubble_avatars', async () => {
  const data = await page.evaluate(() => {
    const messages = document.querySelectorAll('[class*="grid-area:bubble"]');
    const avatars = document.querySelectorAll('[class*="grid-area:avatar"]');
    const incomingAvatars = Array.from(avatars).filter(a => {
      const parent = a.closest('[style*="grid-template-areas"]');
      const style = parent?.getAttribute('style') || '';
      // LEFT orientation has avatar first
      return style.includes('"avatar bubble"');
    });
    const outgoingAvatars = Array.from(avatars).filter(a => {
      const parent = a.closest('[style*="grid-template-areas"]');
      const style = parent?.getAttribute('style') || '';
      return style.includes('"bubble avatar"');
    });
    return {
      totalMessages: messages.length,
      totalAvatars: avatars.length,
      incomingAvatars: incomingAvatars.length,
      outgoingAvatars: outgoingAvatars.length,
    };
  });
  // Crop um bubble incoming
  const firstIncoming = await page.locator('[style*="\\"avatar bubble\\""]').first();
  if ((await firstIncoming.count()) > 0) {
    const box = await firstIncoming.boundingBox();
    if (box) {
      await page.screenshot({
        path: `${OUT}/A2_incoming_with_avatar.png`,
        clip: { x: Math.max(0, box.x - 10), y: Math.max(0, box.y - 10), width: Math.min(700, box.width + 20), height: Math.min(200, box.height + 20) },
      });
    }
  }
  return data;
});

// ============ 3. Hover em variants — coletar bubbles distintos ============
await shoot('A3_variants', async () => {
  const variants = await page.evaluate(() => {
    const all = document.querySelectorAll('[data-bubble-name], [class*="bg-n-solid-blue"], [class*="bg-n-slate-4"], [class*="bg-n-solid-amber"]');
    const list = Array.from(all).slice(0, 20).map(el => {
      const r = el.getBoundingClientRect();
      return {
        cls: el.className.slice(0, 100),
        bgColor: getComputedStyle(el).backgroundColor,
        x: r.x, y: r.y, w: r.width, h: r.height,
      };
    }).filter(b => b.w > 50 && b.h > 20);
    return list.slice(0, 10);
  });
  return { variantsFound: variants.length, samples: variants.slice(0, 5) };
});

// ============ 4. Right-click context menu — Favoritar visível ============
await shoot('A4_contextmenu_star', async () => {
  // Find first message bubble (incoming)
  const bubble = page.locator('[class*="grid-area:bubble"] > div').first();
  const count = await bubble.count();
  if (count === 0) throw new Error('no bubbles');
  // Right click
  await bubble.click({ button: 'right' });
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${OUT}/A4_contextmenu_open.png`, fullPage: false });
  const menuItems = await page.evaluate(() => {
    const menu = document.querySelector('.context-menu, [class*="ContextMenu"], [role="menu"]');
    if (!menu) {
      // Fallback: check any visible portal item
      const items = document.querySelectorAll('button, [role="menuitem"]');
      return Array.from(items)
        .filter(i => /favorit|reply|forward|delete|copiar|copy|encaminhar|excluir/i.test(i.textContent || ''))
        .map(i => i.textContent?.trim()).filter(Boolean);
    }
    return Array.from(menu.querySelectorAll('button, [role="menuitem"]'))
      .map(i => i.textContent?.trim())
      .filter(Boolean);
  });
  // Close menu
  await page.keyboard.press('Escape');
  return { items: menuItems, hasFavoritar: menuItems.some(t => /favorit/i.test(t)) };
});

// ============ 5. Reactions removidas ============
await shoot('A5_no_reactions', async () => {
  const reactions = await page.evaluate(() => ({
    triggerButtons: document.querySelectorAll('.reaction-trigger').length,
    reactionChips: document.querySelectorAll('.reaction-chip').length,
  }));
  return reactions;
});

// ============ 6. Star toggle button removido ============
await shoot('A6_no_star_toggle_floating', async () => {
  const stars = await page.evaluate(() => {
    const allButtons = document.querySelectorAll('button[title*="vorit"], button[title*="emover dos"]');
    // Filtrar apenas os que estão flutuando absoluto sobre bubble
    const floating = Array.from(allButtons).filter(btn => {
      const styles = getComputedStyle(btn.parentElement || btn);
      return styles.position === 'absolute';
    });
    return { totalStarButtons: allButtons.length, floatingStarButtons: floating.length };
  });
  return stars;
});

// ============ 7. Header da conversa — sem sparkle, com mais ações ============
await shoot('A7_header', async () => {
  const headerCheck = await page.evaluate(() => {
    const header = document.querySelector('.conversation--header, header, [class*="conversation-header"]');
    if (!header) return { found: false };
    return {
      found: true,
      sparkleCount: header.querySelectorAll('.i-lucide-sparkles').length,
      searchCount: header.querySelectorAll('.i-lucide-search').length,
    };
  });
  await page.screenshot({
    path: `${OUT}/A7_header.png`,
    clip: { x: 320, y: 0, width: 1100, height: 90 },
  });
  return headerCheck;
});

// ============ 8. ContactInfo painel direito ============
await shoot('A8_contact_panel', async () => {
  const panel = await page.$('.wa-contact-panel');
  if (panel) await panel.screenshot({ path: `${OUT}/A8_contact_panel.png` });
  const banner = await page.evaluate(() => {
    const reply = document.querySelector('[class*="reply-box"], footer');
    return reply ? (reply.innerHTML.toLowerCase().includes('configurada') || reply.innerHTML.toLowerCase().includes('signature')) : false;
  });
  return { panelFound: !!panel, replyBoxBanner: banner };
});

// ============ 9. Galeria — F5 hard via page.reload, capturar skeleton ============
await shoot('A9_gallery_skeleton', async () => {
  await page.route('**/api/v1/accounts/*/attachments**', async route => {
    await new Promise(r => setTimeout(r, 4000));
    return route.continue();
  });
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/gallery`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForTimeout(2500);
  const sk = await page.evaluate(() => {
    const status = document.querySelector('[role="status"][aria-busy="true"]');
    return {
      exists: !!status,
      pulseElements: document.querySelectorAll('.animate-pulse').length,
    };
  });
  await page.screenshot({ path: `${OUT}/A9_gallery_skeleton.png`, fullPage: false });
  await page.unroute('**/api/v1/accounts/*/attachments**');
  return sk;
});

// ============ 10. Galeria carregada ============
await shoot('A10_gallery_loaded', async () => {
  await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/gallery`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  const data = await page.evaluate(() => ({
    cards: document.querySelectorAll('.grid article').length,
    contentVis: getComputedStyle(document.querySelector('.grid article') || document.body).contentVisibility,
  }));
  await page.screenshot({ path: `${OUT}/A10_gallery_loaded.png`, fullPage: false });
  return data;
});

// ============ 11. Galeria — tabs Documentos e Links ============
await shoot('A11_gallery_documents', async () => {
  await page.click('button:has-text("Documentos")').catch(() => {});
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${OUT}/A11_gallery_documents.png`, fullPage: false });
  return {};
});

await shoot('A12_gallery_links', async () => {
  await page.click('button:has-text("Links")').catch(() => {});
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${OUT}/A12_gallery_links.png`, fullPage: false });
  return {};
});

// ============ Console final ============
audit.console = {
  totalErrors: consoleMsgs.filter(m => m.startsWith('[error]')).length,
  totalWarnings: consoleMsgs.filter(m => m.startsWith('[warning]')).length,
  voiceCallButton: consoleMsgs.filter(m => m.includes('VoiceCallButton')).length,
  dateSeparator: consoleMsgs.filter(m => m.includes('DateSeparator')).length,
  fragmentRoot: consoleMsgs.filter(m => m.includes('Extraneous')).length,
  unknownComponent: consoleMsgs.filter(m => m.includes('Failed to resolve')).length,
  messages: consoleMsgs.slice(-30),
};

writeFileSync(`${OUT}/audit.json`, JSON.stringify(audit, null, 2));
console.log('\n=== AUDIT SUMMARY ===');
console.log('Steps:', audit.steps.length, 'OK:', audit.steps.filter(s => s.ok).length);
console.log('Console:', audit.console);

await browser.close();
