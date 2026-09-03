/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo dos aceites 3 e 8 do bloco 2.05 (§C.9 do plano 22).
 *
 *   3. `outline-width > 0` E `outline-color` não transparente no textarea focado
 *   8. em 375 px, anexo, emoji e enviar medem >= 44x44
 *
 * Os dois são invisíveis para jsdom: um é cascade com pseudo-classe, o outro é
 * caixa. E o 3 tem história — `15 §A5.3` mediu que o `outline` computado do
 * composer era `rgba(0,0,0,0) solid 2px`: um anel de 2 px TRANSPARENTE, que
 * passa em qualquer teste de marcação e é invisível para quem navega por
 * teclado.
 *
 * O CSS vem dos `<style scoped>` dos PRIMITIVOS reais, compilado na mesma ordem
 * do build: sass resolve o aninhamento, Tailwind resolve o `@apply`.
 *
 *   node app/javascript/widget/components/specs/browser/composer-geometry.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('não achei a raiz do repositório');
    dir = acima;
  }
  return dir;
})();
const sass = require(
  join(repoRoot, 'node_modules/.pnpm/sass@1.79.3/node_modules/sass')
);

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

const primitivo = nome =>
  readFileSync(join(repoRoot, 'app/javascript/widget/ui', nome), 'utf8');

const estiloDe = sfc =>
  /<style scoped lang="scss">([\s\S]*?)<\/style>/.exec(sfc)?.[1] ?? '';

// sass primeiro (resolve `&__campo` e `&:focus-visible`), Tailwind depois
// (resolve `@apply`) — a mesma ordem do build do Vite.
const scss = `${estiloDe(primitivo('WComposer.vue'))}\n${estiloDe(primitivo('WIconButton.vue'))}`;
const cssComApply = sass.compileString(scss, { style: 'expanded' }).css;

const dir = mkdtempSync(join(tmpdir(), 'composer-geometry-'));
const entrada = join(dir, 'in.css');
const saida = join(dir, 'out.css');
writeFileSync(entrada, `@tailwind utilities;\n${cssComApply}`);
execFileSync(
  'pnpm',
  ['exec', 'tailwindcss', '-c', 'tailwind.widget.config.js', '-i', entrada, '-o', saida],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(saida, 'utf8');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 375, height: 700 } });

// Os tokens de foco como `_tokens.scss` os declara — o anel só é medível se a
// variável existir; sem ela o navegador descarta a declaração inteira.
await page.setContent(`<!doctype html>
<html><head><style>
  :root {
    --w-focus-ring-color: #1d824a;
    --w-focus-ring-width: 2px;
    --w-focus-ring-offset: 2px;
    --w-brand: #2dc46f;
    --w-on-brand: #000000;
  }
  * { box-sizing: border-box; }
  body { margin: 0; }
  ${CSS}
</style></head>
<body>
  <div class="w-composer">
    <textarea id="campo" class="w-composer__campo" rows="1"></textarea>
    <div class="w-composer__acoes">
      <button id="anexar" class="w-icon-button w-icon-button--md">A</button>
      <button id="emoji" class="w-icon-button w-icon-button--md">E</button>
      <button id="enviar" class="w-icon-button w-icon-button--md">S</button>
    </div>
  </div>
</body></html>`);
await page.locator('#campo').waitFor({ state: 'visible' });

// ── Aceite 8: os três alvos em 375 px ───────────────────────────────────────
const caixas = await Promise.all(
  ['#anexar', '#emoji', '#enviar'].map(async id => [
    id,
    await page.$eval(id, el => {
      const r = el.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height) };
    }),
  ])
);
caixas.forEach(([id, c]) =>
  check(`em 375 px, ${id} mede ao menos 44x44`, `${c.w >= 44 && c.h >= 44}`, 'true')
);

// ── Aceite 3: o anel de foco desenha de verdade ─────────────────────────────
await page.focus('#campo');
const anel = await page.$eval('#campo', el => {
  const s = getComputedStyle(el);
  return { largura: s.outlineWidth, cor: s.outlineColor, estilo: s.outlineStyle };
});
check('o textarea focado tem anel com largura > 0', String(parseFloat(anel.largura) > 0), 'true');
check('e a cor do anel NÃO é transparente', anel.cor, 'rgb(29, 130, 74)');
check('e o estilo não é `none`', anel.estilo, 'solid');

// ── O campo tem 16 px: é o que dispensa o trava-zoom do 2.09 ────────────────
check(
  'a fonte do campo é 16 px — abaixo disso o iOS dá auto-zoom ao focar',
  await page.$eval('#campo', el => getComputedStyle(el).fontSize),
  '16px'
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(`\n${results.length - falhas.length}/${results.length} asserções passaram`);
process.exit(falhas.length ? 1 : 0);
