/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e colada
   no relatório do bloco. Não é log esquecido em código de produção. */
/**
 * Mecanismo de aceite do bloco 3.10 — a parte que o jsdom NÃO consegue provar.
 *
 * O `previewTokens.spec.js` compara os dois SCSS declaração a declaração, e
 * isso é leitura de FONTE. Nesta base, leitura de fonte já deu verde três vezes
 * sobre tela errada, e o defeito deste bloco é exatamente do tipo que só o
 * cascade revela: o preview escrevia `--w-brand-readable` em estilo INLINE, e
 * estilo inline vence qualquer classe do MESMO elemento. Toda a paleta escura
 * podia estar correta no arquivo e o texto continuava saindo no legível CLARO.
 *
 * Aqui o Chromium responde qual cor SAIU, nos três cenários:
 *
 *   1. o WIDGET escuro (a verdade: `_tokens.scss` + o `<style>` que
 *      `WidgetTokens` emite, exatamente como `show.html.erb` os ordena);
 *   2. o preview escuro DEPOIS deste bloco;
 *   3. o preview escuro ANTES — tema e tokens no mesmo elemento, que é a
 *      árvore que este bloco encontrou.
 *
 * O número que interessa é o contraste do texto legível contra a superfície
 * escura do widget (`WidgetTokens::SURFACE_DARK`).
 *
 *   node app/javascript/dashboard/modules/widget-preview/specs/browser/dark-brand-readable.check.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('nao achei a raiz do repositorio');
    dir = acima;
  }
  return dir;
})();
const sassDir = require('node:fs')
  .readdirSync(join(repoRoot, 'node_modules/.pnpm'))
  .find(d => /^sass@/.test(d));
const sass = require(
  join(repoRoot, 'node_modules/.pnpm', sassDir, 'node_modules/sass')
);

const results = [];
const check = (name, actual, expected) => {
  const ok = String(actual) === String(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// ── 1. A verdade do servidor sai do RUBY, não de uma cópia em JS ─────────────
// `WidgetTokens` é o objeto que escreve o `<style>` do widget em produção.
// Reimplementar a derivação aqui seria medir o preview contra uma segunda
// cópia da regra — que é a dívida que este bloco existe para fechar.
const rubi = expr =>
  execFileSync(
    'ruby',
    [
      '-e',
      `require 'json'; require './app/services/widget_tokens'; print(${expr})`,
    ],
    { cwd: repoRoot, encoding: 'utf8' }
  );
const CSS_DO_SERVIDOR = rubi("WidgetTokens.new('#2dc46f').css");
const SURFACE_DARK = rubi('WidgetTokens::SURFACE_DARK');
const TOKENS_DO_SERVIDOR = JSON.parse(
  rubi("WidgetTokens.new('#2dc46f').root_tokens.to_json")
);

// ── 2. As folhas de estilo REAIS dos dois lados ──────────────────────────────
const CSS_DO_WIDGET = sass.compile(
  join(repoRoot, 'app/javascript/widget/assets/scss/_tokens.scss'),
  { style: 'expanded', loadPaths: [repoRoot] }
).css;

const sfc = readFileSync(
  new URL('../../components/Widget.vue', import.meta.url),
  'utf8'
);
const blocoDoSfc = /<style scoped lang="scss">([\s\S]*?)<\/style>/.exec(sfc)[1];
const CSS_DO_PREVIEW = sass.compileString(blocoDoSfc, {
  style: 'expanded',
  url: new URL('../../components/Widget.vue', import.meta.url),
}).css;

// O estilo inline do preview é o `brandTokens()` do próprio componente. Aqui
// ele vem do Ruby (mesma derivação, mesmas chaves) — se as duas contas
// divergirem, `useContrast.spec.js` já reprova, e este verificador não precisa
// repetir a comparação.
const INLINE = Object.entries(TOKENS_DO_SERVIDOR)
  .map(([k, v]) => `${k}: ${v}`)
  .join('; ');

// A declaração que o Tailwind emite para `text-w-brand-readable`, lida do
// `theme/colors.js` em vez de decorada — inclusive o FALLBACK, que é parte do
// que o navegador resolve.
const colorsJs = readFileSync(join(repoRoot, 'theme/colors.js'), 'utf8');
const VALOR_READABLE = /readable:\s*'([^']+)'/.exec(colorsJs)[1];
console.log(
  `\ntheme/colors.js -> text-w-brand-readable = color: ${VALOR_READABLE}\n`
);

// ── 3. Contraste WCAG, para o resultado ser um número e não uma impressão ────
const canal = c => {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};
const luminancia = rgb =>
  0.2126 * canal(rgb[0]) + 0.7152 * canal(rgb[1]) + 0.0722 * canal(rgb[2]);
const paraRgb = texto => {
  const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(texto);
  if (m) return [+m[1], +m[2], +m[3]];
  const h = /^#?([0-9a-f]{6})$/i.exec(texto.trim());
  if (!h) throw new Error(`cor irreconhecivel: ${texto}`);
  return [0, 2, 4].map(i => parseInt(h[1].slice(i, i + 2), 16));
};
const contraste = (a, b) => {
  const [x, y] = [luminancia(paraRgb(a)), luminancia(paraRgb(b))];
  const [claro, escuro] = x > y ? [x, y] : [y, x];
  return (claro + 0.05) / (escuro + 0.05);
};
const doisDec = n => (Math.round(n * 100) / 100).toFixed(2);

// ── 4. Mede no navegador ─────────────────────────────────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

await page.setContent(`<!doctype html>
<html class="dark"><head><style>
${CSS_DO_WIDGET}
/* O style do servidor vem DEPOIS e FORA de @layer, como no
   show.html.erb — é o que o faz vencer o @layer base. */
${CSS_DO_SERVIDOR}
${CSS_DO_PREVIEW}
</style></head>
<body style="margin:0">
  <!-- 1. o widget de verdade -->
  <span id="widget" style="color: ${VALOR_READABLE}">legivel</span>

  <!-- 2. o preview DEPOIS deste bloco: tokens fora, tema no filho -->
  <div class="wp-tokens" style="${INLINE}">
    <div class="wp-theme-dark">
      <span id="preview-depois" style="color: ${VALOR_READABLE}">legivel</span>
      <span id="preview-fundo" style="background: rgb(var(--solid-1))">f</span>
    </div>
  </div>

  <!-- 3. o preview ANTES: tema e tokens no MESMO elemento -->
  <div class="wp-tokens wp-theme-dark" style="${INLINE}">
    <span id="preview-antes" style="color: ${VALOR_READABLE}">legivel</span>
  </div>
</body></html>`);

await page.locator('#widget').waitFor({ state: 'visible' });
const cor = sel =>
  page.$eval(sel, el => getComputedStyle(el).getPropertyValue('color'));

const fundo = sel =>
  page.$eval(sel, el =>
    getComputedStyle(el).getPropertyValue('background-color')
  );

const doWidget = await cor('#widget');
const depois = await cor('#preview-depois');
const antes = await cor('#preview-antes');

// O denominador que o visitante realmente ve: o painel escuro do widget.
const PAINEL = await fundo('#preview-fundo');
console.log(`SURFACE_DARK (o alvo da derivacao do servidor) = ${SURFACE_DARK}`);
console.log(`painel escuro do widget  (--solid-1 escuro)    = ${PAINEL}\n`);
console.log(
  `  widget escuro        cor=${doWidget}  contraste=${doisDec(contraste(doWidget, SURFACE_DARK))}:1`
);
console.log(
  `  preview ANTES        cor=${antes}  contraste=${doisDec(contraste(antes, SURFACE_DARK))}:1`
);
console.log(
  `  preview DEPOIS       cor=${depois}  contraste=${doisDec(contraste(depois, SURFACE_DARK))}:1\n`
);
console.log(`  contra o PAINEL escuro (${PAINEL}):`);
console.log(
  `  preview ANTES        contraste=${doisDec(contraste(antes, PAINEL))}:1`
);
console.log(
  `  preview DEPOIS       contraste=${doisDec(contraste(depois, PAINEL))}:1\n`
);

check(
  'o preview escuro pinta a MESMA cor que o widget escuro',
  depois,
  doWidget
);
check(
  'e o defeito existia: a estrutura anterior pintava OUTRA cor',
  antes === doWidget,
  false
);
check(
  'o legivel do preview escuro passa 4,5:1 contra a superficie escura',
  contraste(depois, SURFACE_DARK) >= 4.5,
  true
);
check(
  'a estrutura anterior REPROVAVA 4,5:1 — o defeito era visivel, nao teorico',
  contraste(antes, SURFACE_DARK) >= 4.5,
  false
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} verificacoes ok`
);
process.exit(falhas.length ? 1 : 0);
