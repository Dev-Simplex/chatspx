// Inspeção visual focada no painel direito (B2 — VoiceCallButton)
import { chromium } from 'playwright';

const BASE = process.env.CW_BASE || 'https://hmlchat.simplexsolucoes.com.br';
const ACCOUNT_ID = Number(process.env.CW_ACCOUNT_ID || 5);

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
  if (msg.type() === 'warning' || msg.type() === 'error') consoleMsgs.push(`[${msg.type()}] ${msg.text()}`);
});

await page.goto(`${BASE}/app/accounts/${ACCOUNT_ID}/conversations/307`, {
  waitUntil: 'domcontentloaded',
  timeout: 60000,
});
await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(4500);

// Procurar contact panel
const panel = await page.evaluate(() => {
  // Tentar várias keywords
  const candidates = Array.from(document.querySelectorAll('aside, [class*="contact"], [class*="conversation--details"]'));
  const visible = candidates.filter(c => {
    const r = c.getBoundingClientRect();
    return r.width > 100 && r.height > 100;
  });
  return visible.map(el => ({
    tag: el.tagName,
    cls: el.className,
    width: el.getBoundingClientRect().width,
    height: el.getBoundingClientRect().height,
  }));
});
console.log('PANELS:', JSON.stringify(panel, null, 2));

// Buscar VoiceCallButton ou ícone telefone no painel direito
const phoneCheck = await page.evaluate(() => {
  const panel = document.querySelector('.wa-contact-panel');
  if (!panel) return { foundPanel: false };
  const phone = panel.querySelectorAll('.i-lucide-phone, [class*="phone"], button[title*="hamada"], button[title*="all"]');
  const items = Array.from(phone).map(p => ({
    tag: p.tagName,
    cls: p.className.slice(0, 100),
    title: p.getAttribute('title'),
  }));
  // Custom element não-resolvido seria <voicecallbutton>
  const unresolved = panel.querySelectorAll('voicecallbutton');
  return {
    foundPanel: true,
    panelRect: panel.getBoundingClientRect(),
    phoneCount: phone.length,
    items,
    unresolvedVoiceCallButton: unresolved.length,
  };
});
console.log('PHONE CHECK:', JSON.stringify(phoneCheck, null, 2));

await page.screenshot({ path: '/tmp/smoke_2026_04_28/09_B2_full_view.png', fullPage: false });

// Crop só do painel direito
const panelEl = await page.$('.wa-contact-panel');
if (panelEl) {
  await panelEl.screenshot({ path: '/tmp/smoke_2026_04_28/10_B2_contact_panel.png' });
}

console.log('CONSOLE:', consoleMsgs.slice(-20).join('\n'));
console.log('VCB warnings count:', consoleMsgs.filter(m => m.includes('VoiceCallButton')).length);
console.log('DateSeparator warnings count:', consoleMsgs.filter(m => m.includes('DateSeparator')).length);
await browser.close();
