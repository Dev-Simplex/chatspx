/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e colada
   no relatório do bloco. Não é log esquecido em código de produção. */
/**
 * Mecanismo de aceite do bloco 3.16 — a parte que o jsdom NÃO consegue provar.
 *
 * O `WidgetPreChat.spec.js` verifica ESTRUTURA: quais campos aparecem, em que
 * ordem, com que texto. Isso o jsdom faz bem. O que ele não faz é resolver
 * cascata, `!important` e custom property — e é exatamente ali que esta base já
 * se machucou três vezes, sempre com a mesma forma: regra ampla com
 * `!important` no skin, componente correto, teste verde, tela errada.
 *
 * O caso concreto aqui: `_wa-skin.scss` tem, sob `.dark`, regras como
 *
 *     [class*='text-n-slate-12'] { color: #e9edef !important; }
 *     .bg-n-solid-1 { background-color: #111b21 !important; }
 *
 * O preview ganhou tema PRÓPRIO no bloco 3.10 (`.wp-theme-light` /
 * `.wp-theme-dark`), independente do tema do painel. Com o painel escuro e o
 * preview claro, qualquer superfície do preview que use classe `n-*` fica presa
 * na cor do PAINEL, mesmo herdando a custom property correta — porque
 * `!important` vence a variável.
 *
 * Este arquivo pergunta ao Chromium qual cor SAIU, em vez de ler a folha de
 * estilo e concluir.
 *
 *   node app/javascript/dashboard/modules/widget-preview/specs/browser/prechat-preview-colors.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
// A raiz sai de subir ate o `package.json`, e nao de uma contagem de `../`:
// contar niveis quebra em silencio quando o arquivo muda de pasta.
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

/**
 * Mede e IMPRIME sem reprovar.
 *
 * Existe para uma superfície vizinha que este bloco não é dono: reprovar aqui
 * sequestraria o gate de outra trilha, e apagar a medição esconderia que o par
 * texto/fundo depende das duas. O número fica à vista; a decisão é de quem tem
 * o arquivo.
 */
const diagnostico = (name, actual, expected, dono) => {
  const ok = actual === expected;
  console.log(
    `${ok ? '  ok  ' : ' NOTA '} ${name}\n        esperado=${expected}  recebido=${actual}\n        superfície de ${dono}`
  );
};

// ── 1. As classes saem do COMPONENTE, não de uma fixture ─────────────────────
// Se alguém trocar as classes do preview, este teste mede as novas em vez de
// continuar medindo uma cópia que só existe aqui dentro.
const componente = readFileSync(
  new URL('../../components/WidgetPreChatPreview.vue', import.meta.url),
  'utf8'
);

const classesDoTestId = testId => {
  const tag = new RegExp(`<[^>]*data-testid="${testId}"[^>]*>`).exec(componente);
  if (!tag) throw new Error(`não achei a tag com data-testid="${testId}"`);
  const cls = /class="([^"]*)"/.exec(tag[0]);
  if (!cls) throw new Error(`a tag ${testId} não tem class`);
  return cls[1].replace(/\s+/g, ' ').trim();
};

const CLASSE_ROTULO = classesDoTestId('prechat-preview-label');
const CLASSE_CAMPO = classesDoTestId('prechat-preview-placeholder');
const CLASSE_BOTAO = classesDoTestId('prechat-preview-submit');
const CLASSE_RAIZ = classesDoTestId('prechat-preview');

// ── 2. O CSS de verdade: utilities do dashboard + skin + paleta do preview ───
const dir = mkdtempSync(join(tmpdir(), 'prechat-preview-'));
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

// O `<style scoped>` do PRÓPRIO componente. Sem ele o harness mediria um
// componente sem as classes que o pintam — e daria um vermelho falso.
//
// O `scoped` some aqui, e é uma diferença declarada entre harness e app: no
// app o Vue reescreve `.wp-pc-strong` como `.wp-pc-strong[data-v-hash]`, o que
// SOBE a especificidade. Medir sem o atributo é o caso mais DESFAVORÁVEL dos
// dois, então um verde aqui não esconde um vermelho lá.
const ESTILO_DO_COMPONENTE = /<style scoped>([\s\S]*?)<\/style>/.exec(
  componente
)[1];

// A mesma declaração do `<style scoped>` do `Widget.vue` do preview (3.10).
const PALETA = sass.compileString(
  `@import '${join(repoRoot, 'app/javascript/widget/assets/scss/tokens_values')}';
   .wp-theme-light { @include widget-palette-light; }
   .wp-theme-dark { @include widget-palette-dark; }`,
  { style: 'expanded', loadPaths: [repoRoot] }
).css;

// ── 3. Mede no navegador, com o PAINEL ESCURO e o PREVIEW CLARO ──────────────
// É a combinação que o 3.10 tornou possível e que nenhum teste de jsdom vê.
const browser = await chromium.launch();
const page = await browser.newPage();

await page.setContent(`<!doctype html>
<html class="dark"><head><style>
${TAILWIND}
${SKIN}
${PALETA}
${ESTILO_DO_COMPONENTE}
</style></head>
<body style="margin:0">
  <div class="wp-theme-light" style="--w-brand: #2dc46f; --w-on-brand: #000000">
    <div id="wrapper" class="widget-wrapper bg-n-solid-1">
      <div class="${CLASSE_RAIZ}">
        <div data-testid="prechat-preview-field">
          <span id="rotulo" class="${CLASSE_ROTULO}">Nome</span>
          <div id="campo" class="${CLASSE_CAMPO}">Digite seu nome</div>
        </div>
        <button id="botao" class="${CLASSE_BOTAO}">Iniciar conversa</button>
      </div>
    </div>
  </div>
</body></html>`);

await page.locator('#botao').waitFor({ state: 'visible' });

const computed = (selector, prop) =>
  page.$eval(
    selector,
    (el, property) => getComputedStyle(el).getPropertyValue(property),
    prop
  );

// Os valores esperados são os do TEMA CLARO DO WIDGET
// (`_tokens_values.scss`, mixin `widget-palette-light`), porque é o tema que o
// preview está mostrando — e não os do painel.
diagnostico(
  'fundo do painel do preview segue o tema do PREVIEW, não o do dashboard',
  await computed('#wrapper', 'background-color'),
  'rgb(255, 255, 255)', // --solid-1 claro
  '`Widget.vue` (bloco 3.10) — `.widget-wrapper` usa `bg-n-solid-1`, que o skin prende em #111b21 sob `.dark`'
);
check(
  'rótulo do campo usa o texto do tema claro do widget',
  await computed('#rotulo', 'color'),
  'rgb(28, 32, 36)' // --slate-12 claro
);
check(
  'texto de exemplo do campo usa o cinza do tema claro do widget',
  await computed('#campo', 'color'),
  'rgb(128, 131, 141)' // --slate-10 claro
);
check(
  'botão de enviar pinta com a cor da marca',
  await computed('#botao', 'background-color'),
  'rgb(45, 196, 111)' // --w-brand
);
check(
  'texto do botão usa a cor legível sobre a marca',
  await computed('#botao', 'color'),
  'rgb(0, 0, 0)' // --w-on-brand
);

// ── 4. O tema INVERSO: painel claro, preview escuro ──────────────────────────
// O catch-all só existe sob `.dark`, então este lado não tem `!important` — mas
// tem a outra metade da pergunta: as classes próprias precisam seguir o tema do
// PREVIEW, e não ficar presas no claro do painel.
await page.setContent(`<!doctype html>
<html><head><style>
${TAILWIND}
${SKIN}
${PALETA}
${ESTILO_DO_COMPONENTE}
</style></head>
<body style="margin:0">
  <div class="wp-theme-dark" style="--w-brand: #2dc46f; --w-on-brand: #000000">
    <div class="${CLASSE_RAIZ}">
      <span id="rotulo" class="${CLASSE_ROTULO}">Nome</span>
      <div id="campo" class="${CLASSE_CAMPO}">Digite seu nome</div>
    </div>
  </div>
</body></html>`);
await page.locator('#rotulo').waitFor({ state: 'visible' });

check(
  'com o painel CLARO e o preview ESCURO, o rótulo segue o preview',
  await computed('#rotulo', 'color'),
  'rgb(237, 238, 240)' // --slate-12 escuro
);
check(
  'com o painel CLARO e o preview ESCURO, o texto de exemplo segue o preview',
  await computed('#campo', 'color'),
  'rgb(119, 123, 132)' // --slate-10 escuro
);

await browser.close();

// ── 5. Trava de regressão, sobre o arquivo ───────────────────────────────────
// A medição acima só é verde enquanto o componente não voltar a usar classe de
// COR `n-*`. Esta asserção textual é o que impede a volta silenciosa — e ela
// olha o template, não os comentários, que citam os nomes ao explicar o porquê.
const template = /<template>([\s\S]*?)<\/template>/.exec(componente)[1];
const classesDeCorProibidas = [
  ...template.matchAll(/\b(?:text|bg|border|outline)-n-[a-z]+-\d+\b/g),
].map(m => m[0]);
check(
  'nenhuma classe de cor `n-*` no template do preview do pré-chat',
  classesDeCorProibidas.join(',') || 'nenhuma',
  'nenhuma'
);

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
process.exit(falhas.length ? 1 : 0);
