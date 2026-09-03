/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * Bloco 5.23 — o que o jsdom NÃO prova da seção "recebido do site".
 *
 * `SiteContext.spec.js` cobre a lógica: quais linhas aparecem, o que fica de fora, `nao_disponivel`
 * traduzido. Nada disso resolve cascata, custom property ou contraste — e é exatamente aí que o
 * bloco 1.17 reprovou: o selo dele saiu com **4,14** de razão no tema claro, abaixo do mínimo de
 * 4,5 do WCAG AA para texto pequeno. O DOM dizia que o selo existia; a tela mostrava um cinza
 * ilegível. Trinta testes de unidade tinham passado.
 *
 * Este selo é uma combinação NOVA (`text-n-slate-12` sobre `bg-n-slate-3`), então herda o risco
 * inteiro e precisa da mesma medição — nos dois temas.
 *
 * As classes NÃO são copiadas para cá: saem do `SiteContext.vue` real por regex. Copiá-las mediria
 * uma fixture, e a fixture continuaria verde depois de alguém trocar a cor no componente.
 *
 *   node app/javascript/dashboard/routes/dashboard/conversation/contact/specs/browser/site-context-contrast.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
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

// ── 1. As classes saem do componente REAL ───────────────────────────────────────────────────
const componente = readFileSync(
  join(
    repoRoot,
    'app/javascript/dashboard/routes/dashboard/conversation/contact/SiteContext.vue'
  ),
  'utf8'
);
const classeDoSelo = /<span\s+class="([^"]+)"/.exec(componente)[1];
const classeDoTitulo = /<h4 class="([^"]+)"/.exec(componente)[1];

console.log(`\n5.23 — contraste da seção, em Chromium real\n`);
console.log(`        selo:   ${classeDoSelo}`);
console.log(`        título: ${classeDoTitulo}\n`);

// ── 2. O CSS de verdade ─────────────────────────────────────────────────────────────────────
const dir = mkdtempSync(join(tmpdir(), 'site-context-'));
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(inCss, '@tailwind utilities;\n');
execFileSync(
  'pnpm',
  ['exec', 'tailwindcss', '-c', 'tailwind.config.js', '-i', inCss, '-o', outCss],
  { cwd: repoRoot, stdio: 'pipe' }
);
const TAILWIND = readFileSync(outCss, 'utf8');
const SKIN = sass.compile(
  join(repoRoot, 'app/javascript/dashboard/assets/scss/_wa-skin.scss'),
  { style: 'expanded' }
).css;
const NEXT_COLORS = sass.compile(
  join(repoRoot, 'app/javascript/dashboard/assets/scss/_next-colors.scss'),
  { style: 'expanded' }
).css;

// ── 3. Contraste WCAG, calculado no navegador sobre a cor COMPUTADA ─────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

const medirNoTema = async temaEscuro => {
  await page.setContent(`<!doctype html>
<html${temaEscuro ? ' class="dark"' : ''}><head><style>
${NEXT_COLORS}
${TAILWIND}
${SKIN}
</style></head>
<body style="margin:0" class="bg-n-background">
  <div id="secao" class="flex flex-col gap-3 pb-1">
    <span id="selo" class="${classeDoSelo}">Recebido do site</span>
    <h4 id="titulo" class="${classeDoTitulo}">De onde veio esta pessoa</h4>
  </div>
</body></html>`);
  await page.locator('#selo').waitFor({ state: 'visible' });

  return page.evaluate(() => {
    // Luminância relativa e razão de contraste — a fórmula do WCAG 2.1, não uma aproximação.
    const lum = cor => {
      const [r, g, b] = cor.match(/\d+(\.\d+)?/g).map(Number);
      const canal = c => {
        const s = c / 255;
        return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
      };
      return 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
    };
    // O fundo EFETIVO: sobe a árvore até achar quem de fato pinta, porque `transparent`
    // herdaria e o cálculo mediria uma cor que ninguém vê.
    const fundoDe = el => {
      let no = el;
      while (no) {
        const bg = getComputedStyle(no).backgroundColor;
        if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
        no = no.parentElement;
      }
      return 'rgb(255, 255, 255)';
    };
    const razao = id => {
      const el = document.getElementById(id);
      const a = lum(getComputedStyle(el).color);
      const b = lum(fundoDe(el));
      const [claro, escuro] = a > b ? [a, b] : [b, a];
      return Math.round(((claro + 0.05) / (escuro + 0.05)) * 100) / 100;
    };
    const caixa = id => document.getElementById(id).getBoundingClientRect();

    return {
      selo: razao('selo'),
      titulo: razao('titulo'),
      corDoSelo: getComputedStyle(document.getElementById('selo')).color,
      fundoDoSelo: getComputedStyle(document.getElementById('selo'))
        .backgroundColor,
      // O selo do 1.17 ficava POR BAIXO do botão de excluir. Aqui não há botão, mas a caixa
      // precisa existir de verdade: largura zero é selo que o DOM tem e a tela não mostra.
      seloTemCaixa: caixa('selo').width > 0 && caixa('selo').height > 0,
      seloAcimaDoTitulo: caixa('selo').bottom <= caixa('titulo').top,
    };
  });
};

const MINIMO_AA = 4.5;

for (const [nome, escuro] of [
  ['claro', false],
  ['escuro', true],
]) {
  const m = await medirNoTema(escuro);
  console.log(
    `· tema ${nome} — selo ${m.corDoSelo} sobre ${m.fundoDoSelo}`
  );
  check(
    `[${nome}] o selo passa em WCAG AA (>= ${MINIMO_AA}) — razão ${m.selo}`,
    String(m.selo >= MINIMO_AA),
    'true'
  );
  check(
    `[${nome}] o título de seção passa em WCAG AA — razão ${m.titulo}`,
    String(m.titulo >= MINIMO_AA),
    'true'
  );
  check(`[${nome}] o selo ocupa caixa de verdade`, String(m.seloTemCaixa), 'true');
  check(
    `[${nome}] o selo fica ACIMA do primeiro título, sem sobrepor`,
    String(m.seloAcimaDoTitulo),
    'true'
  );
}

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram em navegador real\n`
);
process.exit(falhas.length ? 1 : 0);
