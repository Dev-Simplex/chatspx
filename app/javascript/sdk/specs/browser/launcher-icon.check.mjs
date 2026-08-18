/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 3.19 — asserções 7 e 8, MEDIDAS no navegador.
 *
 * POR QUE ESTE ARQUIVO EXISTE. As asserções 7 (anel ≥ 3:1) e 8 (`object-fit:
 * cover` no círculo de 64 px) estavam provadas por REGEX na string do `SDK_CSS`.
 * Isso é ler a regra e concluir — não chega nem a ser jsdom. Não prova que a
 * cascata resolveu, que a custom property caiu no fallback, que `all: revert`
 * não comeu o `object-fit`, nem que a foto retangular de fato vira quadrado.
 *
 * A base já foi mordida três vezes por catch-all de CSS com `!important`:
 * componente certo, teste verde, tela errada. Aqui quem responde é o Chromium.
 *
 * Extensão `.check.mjs` de propósito: fora do `include` do vitest, roda com
 * `node`, NÃO carrega `playwright.config.js` e portanto não sobe `webServer`
 * nem toca nas portas fixas compartilhadas.
 *
 *   node app/javascript/sdk/specs/browser/launcher-icon.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';

const source = readFileSync(new URL('../../sdk.js', import.meta.url), 'utf8');
const match = source.match(/export const SDK_CSS = `([\s\S]*?)\n`;/);
if (!match) {
  console.error('FALHA: não consegui extrair SDK_CSS de sdk.js');
  process.exit(1);
}
const SDK_CSS = match[1];

const BRAND = '#2dc46f';
const ON_BRAND = '#000000';

const results = [];
const check = (name, actual, expected) => {
  const ok = String(actual) === String(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};
const checkWith = (name, ok, detail) => {
  results.push({ name, ok });
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}\n        ${detail}`);
};

// ── contraste WCAG sobre valores MEDIDOS, não sobre literais digitados ──────
const ch = c => {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};
const lum = ([r, g, b]) => 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
const ratio = (a, b) => {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};
const over = ([r, g, b, a], [br, bg, bb]) => [
  a * r + (1 - a) * br,
  a * g + (1 - a) * bg,
  a * b + (1 - a) * bb,
];
/** Extrai as cores rgb()/rgba() na ordem em que o motor as devolveu. */
const parseColors = shadow =>
  [...shadow.matchAll(/rgba?\(([^)]+)\)/g)].map(m =>
    m[1].split(',').map(v => Number.parseFloat(v.trim()))
  );

const browser = await chromium.launch();
const page = await browser.newPage();

await page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0;background:#ffffff">
  <div id="cw-bubble-holder" style="--w-brand:${BRAND}; --w-on-brand:${ON_BRAND};">
    <button id="foto" class="woot-widget-bubble woot-widget-bubble--has-photo woot-elements--right">
      <img class="woot-widget-bubble__photo" alt="" aria-hidden="true" />
    </button>
    <button id="balao" class="woot-widget-bubble woot-elements--right">
      <svg id="svg" width="24" height="24" viewBox="0 0 240 240" fill="none">
        <path d="M240 240H122C56 240 3 187 3 122C3 56 56 3 122 3C187 3 240 56 240 122V240Z" fill="currentColor"/>
      </svg>
    </button>
  </div>
</body></html>`);

// Uma foto RETANGULAR de verdade (200x50), gerada como raster no próprio
// navegador. É o caso que a asserção 8 nomeia: retrato que entortaria o lançador.
await page.evaluate(() => {
  const c = document.createElement('canvas');
  c.width = 200;
  c.height = 50;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#c02020';
  ctx.fillRect(0, 0, 200, 50);
  ctx.fillStyle = '#2040c0';
  ctx.fillRect(0, 0, 100, 50);
  document.querySelector('.woot-widget-bubble__photo').src = c.toDataURL();
});
await page.waitForFunction(
  () => document.querySelector('.woot-widget-bubble__photo').complete
);

const img = page.locator('#foto .woot-widget-bubble__photo');
const foto = page.locator('#foto');

console.log('\n── ASSERÇÃO 8 — object-fit: cover no círculo de 64 px ──');

check(
  'object-fit COMPUTADO na foto (all: revert não o comeu)',
  await img.evaluate(el => getComputedStyle(el).objectFit),
  'cover'
);

const box = await img.evaluate(el => {
  const r = el.getBoundingClientRect();
  return { w: Math.round(r.width), h: Math.round(r.height) };
});
checkWith(
  'a foto 200x50 é RENDERIZADA como 64x64 — não entorta o lançador',
  box.w === 64 && box.h === 64,
  `intrínseco=200x50  renderizado=${box.w}x${box.h}  (esperado 64x64)`
);

check(
  'a foto herda o raio da bolha (recorte circular)',
  await img.evaluate(el => getComputedStyle(el).borderRadius),
  '100px'
);

const bubbleBox = await foto.evaluate(el => {
  const r = el.getBoundingClientRect();
  return { w: Math.round(r.width), h: Math.round(r.height) };
});
checkWith(
  'o círculo de 64 px segue congelado (§8 item 2)',
  bubbleBox.w === 64 && bubbleBox.h === 64,
  `lançador=${bubbleBox.w}x${bubbleBox.h}`
);

check(
  'a bolha recorta o que passa dela',
  await foto.evaluate(el => getComputedStyle(el).overflow),
  'hidden'
);

console.log(
  '\n── ASSERÇÃO 7 — anel ≥ 3:1, com as cores que o motor resolveu ──'
);

const shadow = await foto.evaluate(el => getComputedStyle(el).boxShadow);
console.log(`        box-shadow computado: ${shadow}`);

const colors = parseColors(shadow);
checkWith(
  'o motor resolveu os 3 anéis/sombras da regra',
  colors.length === 3,
  `cores encontradas=${colors.length} → ${JSON.stringify(colors)}`
);

const inner = colors[0];
const outer = colors[1];

checkWith(
  '--w-brand-border caiu no fallback BRANCO (o token não está em WIDGET_TOKEN_NAMES)',
  inner && inner[0] === 255 && inner[1] === 255 && inner[2] === 255,
  `anel interno medido = rgb(${inner?.slice(0, 3).join(', ')})`
);

const outerAlpha = outer?.length === 4 ? outer[3] : 1;
const outerRGB = outer?.slice(0, 3) ?? [0, 0, 0];
const WHITE = [255, 255, 255];
const DARK = [23, 23, 23];
const BRAND_RGB = [45, 196, 111];

const parOuterBrand = ratio(
  over([...outerRGB, outerAlpha], BRAND_RGB),
  BRAND_RGB
);
const parOuterLight = ratio(over([...outerRGB, outerAlpha], WHITE), WHITE);
const parInnerDark = ratio(inner.slice(0, 3), DARK);
const parRingRing = ratio(
  over([...outerRGB, outerAlpha], WHITE),
  inner.slice(0, 3)
);

checkWith(
  'par 1/3 — borda × cor da marca ≥ 3:1',
  parOuterBrand >= 3,
  `medido=${parOuterBrand.toFixed(3)}`
);
checkWith(
  'par 2/3 — borda × fundo claro ≥ 3:1',
  parOuterLight >= 3,
  `medido=${parOuterLight.toFixed(3)}`
);
checkWith(
  'par 3/3 — borda × fundo escuro ≥ 3:1',
  parInnerDark >= 3,
  `medido=${parInnerDark.toFixed(3)}`
);
checkWith(
  'os dois anéis contrastam ENTRE SI ≥ 3:1',
  parRingRing >= 3,
  `medido=${parRingRing.toFixed(3)}`
);

console.log('\n── o balão (modo default) não regrediu ──');

check(
  'o ícone herda --w-on-brand por currentColor (1.05)',
  await page
    .locator('#balao svg path')
    .evaluate(el => getComputedStyle(el).fill),
  'rgb(0, 0, 0)'
);
check(
  'o balão SEM foto não ganha o anel da foto',
  await page.locator('#balao').evaluate(el => {
    const s = getComputedStyle(el).boxShadow;
    return /0px 0px 0px 2px/.test(s) ? 'com anel' : 'sem anel';
  }),
  'sem anel'
);

await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções passaram`
);
if (failed.length) {
  console.error(`FALHOU: ${failed.map(f => f.name).join(' · ')}`);
  process.exit(1);
}
console.log('TODAS as asserções medidas no Chromium passaram.');
