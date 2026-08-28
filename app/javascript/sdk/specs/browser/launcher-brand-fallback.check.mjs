/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado dele, lida por quem roda e colada no relatório do
   bloco. Não é log esquecido em código de produção. */
/**
 * BLOCO 1.03 — o `--w-brand` do `SDK_CSS` precisa de FALLBACK.
 *
 * O CAMINHO DEGRADADO É REAL, não hipotético. `applyWidgetTokens`
 * (`IFrameHelper.js`) só escreve o token se o valor casar `SAFE_TOKEN_VALUE` —
 * hex de 3, 6 ou 8 dígitos, ou uma referência `var(--w-…)`. `widget_color` é
 * uma `string` livre no banco: `rgb(0,156,224)`, `dodgerblue` ou um hex com
 * espaço sobrando são recusados pela fronteira, e com razão (`postMessage` é
 * superfície de entrada). Recusado o token, `background: var(--w-brand)` fica
 * INVÁLIDA no momento de computar o valor — a propriedade cai para o inicial e
 * o lançador de 64 px fica TRANSPARENTE na página do cliente.
 *
 * Este verificador mede os dois mundos no mesmo Chromium:
 *
 *   COM token   → a cor da inbox, em repouso E em `:hover` (é o aceite do 1.05,
 *                 remedido aqui para provar que o fallback não o move);
 *   SEM token   → `#2dc46f`, o `DEFAULT_WIDGET_COLOR` do `Channel::WebWidget`,
 *                 em repouso E em `:hover` — o MESMO valor nos dois estados.
 *
 * A segunda metade é o que separa este fallback da armadilha R2 do plano. Lá o
 * hex estava CRAVADO no `:hover`: pintava mesmo com o token presente, e só no
 * hover — mudança de matiz na mão do visitante. Aqui ele é o segundo argumento
 * de `var()`: com token nunca é lido, e sem token as duas regras caem no mesmo
 * valor. "Mesma cor nos dois estados" é medido, não afirmado.
 *
 *   node app/javascript/sdk/specs/browser/launcher-brand-fallback.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';

const BRAND = '#009CE0';
const BRAND_RGB = 'rgb(0, 156, 224)';
// `DEFAULT_WIDGET_COLOR` de `app/models/channel/web_widget.rb`.
const PADRAO_RGB = 'rgb(45, 196, 111)';
const TRANSPARENTE = 'rgba(0, 0, 0, 0)';
const ON_BRAND = '#000000';

const source = readFileSync(new URL('../../sdk.js', import.meta.url), 'utf8');
const SDK_CSS = source.match(/export const SDK_CSS = `([\s\S]*?)\n`;/)?.[1];
if (!SDK_CSS) {
  console.error('FALHA: não consegui extrair SDK_CSS de sdk.js');
  process.exit(1);
}

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

const browser = await chromium.launch();
const page = await browser.newPage();

// `tokens` vazio reproduz o holder tal como o SDK o deixa quando
// `applyWidgetTokens` não escreveu nada — sem `style` inline nenhum, que é
// exatamente o que aquela função faz ao recusar o valor.
const montar = async tokens =>
  page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0">
  <div id="cw-bubble-holder"${tokens ? ` style="${tokens}"` : ''}>
    <button class="woot-widget-bubble woot-elements--right">
      <svg viewBox="0 0 24 24"><path d="M4 4h16v12H7l-3 3z" fill="currentColor"/></svg>
    </button>
  </div>
</body></html>`);

const bubble = page.locator('.woot-widget-bubble');
const fundo = () => bubble.evaluate(el => getComputedStyle(el).backgroundColor);

/** Repouso e `:hover` do mesmo estado, medidos no mesmo Chromium. */
const medir = async () => {
  await bubble.waitFor({ state: 'visible' });
  const repouso = await fundo();
  await bubble.hover();
  // Âncora de conteúdo, não espera cega. `polling: 500` porque em headless o
  // `waitForFunction` faz polling por `requestAnimationFrame`, que não dispara
  // de forma confiável nesse modo — a mesma nota de `launcher-hover.check.mjs`.
  await page.waitForFunction(
    () => document.querySelector('.woot-widget-bubble:hover') !== null,
    undefined,
    { polling: 500 }
  );
  const hover = await fundo();
  // Tira o mouse de cima para o próximo estado começar limpo.
  await page.mouse.move(0, 0);
  return { repouso, hover };
};

// ── 1. COM token: o fallback não pode se intrometer ────────────────────────
await montar(`--w-brand: ${BRAND}; --w-on-brand: ${ON_BRAND};`);
const comToken = await medir();
check('com token · repouso usa a cor da inbox', comToken.repouso, BRAND_RGB);
check('com token · :hover usa a cor da inbox', comToken.hover, BRAND_RGB);

// ── 2. SEM token: o lançador não pode ficar invisível ──────────────────────
await montar('');
const semToken = await medir();
check(
  'sem token · repouso NÃO é transparente (o defeito que o fallback mata)',
  String(semToken.repouso !== TRANSPARENTE),
  'true'
);
check(
  'sem token · repouso cai no padrão da casa',
  semToken.repouso,
  PADRAO_RGB
);
check('sem token · :hover cai no MESMO padrão', semToken.hover, PADRAO_RGB);
check(
  'sem token · repouso e :hover são a MESMA cor (sem mudança de matiz)',
  semToken.repouso,
  semToken.hover
);

// ── 3. E o fallback tem de estar nas DUAS regras ───────────────────────────
// Sem esta asserção o item 2 passaria com o fallback só no repouso: o `:hover`
// herdaria… nada, e a medição de hover leria a cor de repouso pintada antes.
const semComentarios = SDK_CSS.replace(/\/\*[\s\S]*?\*\//g, '');
const comFallback = (
  semComentarios.match(/background:\s*var\(--w-brand,\s*#2dc46f\)/g) || []
).length;
check('as DUAS regras do lançador têm o fallback', String(comFallback), '2');
check(
  'nenhum `var(--w-brand)` sem fallback sobrou',
  String(/var\(--w-brand\)/.test(semComentarios)),
  'false'
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
if (falhas.length) {
  console.error(`FALHOU: ${falhas.map(f => f.name).join(' · ')}`);
  process.exit(1);
}
console.log('TODAS as asserções medidas no Chromium passaram.');
