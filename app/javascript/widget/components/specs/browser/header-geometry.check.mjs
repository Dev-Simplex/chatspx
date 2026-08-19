/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 2.06 — o que o jsdom NÃO prova.
 *
 * O `header.spec.js` cobre marcação e tradução: quantos `h1`, se o `<main>`
 * existe, se o ponto de status tem nome acessível, se sobrou `text-white` no
 * template. Nada disso precisa de navegador.
 *
 * O resto do aceite é GEOMETRIA e COR COMPUTADA — 56/96 de altura, avatar 32
 * com raio 6, alvos >= 44x44 em 375 px, e a cor do texto vindo de
 * `--w-on-brand`. jsdom não resolve cascade, não aplica utilitária do Tailwind e
 * não calcula caixa: ali um verde seria afirmação, não medição.
 *
 * A COR É MEDIDA COM UMA MARCA CLARA de propósito. Com o verde padrão,
 * `--w-on-brand` é preto e `text-white` cravado saltaria à vista; com uma marca
 * clara, o servidor manda preto e um branco cravado ficaria INVISÍVEL sobre o
 * amarelo — é o caso que quebra a inbox do cliente, e é o que se mede aqui.
 *
 *   node app/javascript/widget/components/specs/browser/header-geometry.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('não achei a raiz do repositório');
    dir = acima;
  }
  return dir;
})();

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};
const checkAtLeast = (name, actual, minimo) => {
  const ok = Number(actual) >= minimo;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado>=${minimo}  recebido=${actual}`
  );
};

// ── 1. As classes saem dos COMPONENTES, nunca de uma fixture ────────────────
const comp = nome =>
  readFileSync(
    join(repoRoot, 'app/javascript/widget/components', nome),
    'utf8'
  );

const chatHeader = comp('ChatHeader.vue');
const headerExpanded = comp('ChatHeaderExpanded.vue');
const headerActions = comp('HeaderActions.vue');

/** A `class="..."` da primeira tag que casa com o padrão dado. */
const classeDe = (fonte, padraoDaTag, rotulo) => {
  const tag = new RegExp(padraoDaTag).exec(fonte);
  if (!tag) throw new Error(`não localizei ${rotulo}`);
  const cls = /class="([^"]*)"/.exec(tag[0]);
  if (!cls) throw new Error(`${rotulo} não tem class`);
  return cls[1].replace(/\s+/g, ' ').trim();
};

const CLASSE_HEADER = classeDe(
  chatHeader,
  '<header[\\s\\S]*?>',
  'o <header> colapsado'
);
const CLASSE_AVATAR = classeDe(
  chatHeader,
  '<img[\\s\\S]*?/>',
  'o avatar do colapsado'
);
const CLASSE_BACK = classeDe(
  chatHeader,
  '<button[\\s\\S]*?>',
  'o botão de voltar'
);
const CLASSE_TITULO = classeDe(
  chatHeader,
  '<h1[\\s\\S]*?/>',
  'o h1 do colapsado'
);
const CLASSE_DOT = classeDe(
  chatHeader,
  '<div\\s+role="img"[\\s\\S]*?/>',
  'o ponto de status'
);
// A cor do titulo mora na LINHA que o contem, nao no `h1`. Cravar esta classe
// aqui foi um ponto cego real deste arquivo: sabotando o componente com
// `text-white`, a medicao continuava verde porque media a fixture, nao o
// componente. Extrair e o que faz a sabotagem doer.
const CLASSE_LINHA_TITULO = classeDe(
  chatHeader,
  '<div\\s+data-testid="header-title-row"[\\s\\S]*?>',
  'a linha do titulo'
);
const CLASSE_HEADER_EXP = classeDe(
  headerExpanded,
  '<header[\\s\\S]*?>',
  'o <header> expandido'
);
const CLASSE_ACAO = classeDe(
  headerActions,
  '<button[\\s\\S]*?>',
  'um botão de ação'
);

// ── 2. O CSS do widget, compilado com o config DELE ─────────────────────────
// `tailwind.widget.config.js` tem `content` restrito (bloco 1.08). Compilar com
// o config do dashboard geraria classes que o widget não recebe no navegador.
const dir = mkdtempSync(join(tmpdir(), 'header-geometry-'));
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(inCss, '@tailwind utilities;\n');
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.widget.config.js',
    '-i',
    inCss,
    '-o',
    outCss,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(outCss, 'utf8');

// ── 3. Mede no navegador ────────────────────────────────────────────────────
const browser = await chromium.launch();

// Marca CLARA: é o servidor que decide a cor legível sobre ela (bloco 1.02).
const MARCA = '#ffe600';
const SOBRE_A_MARCA = '#000000';

const pagina = async largura => {
  const page = await browser.newPage({
    viewport: { width: largura, height: 700 },
  });
  await page.setContent(`<!doctype html>
<html><head><style>
  :root { --w-brand: ${MARCA}; --w-on-brand: ${SOBRE_A_MARCA}; }
  * { box-sizing: border-box; }
  body { margin: 0; }
  ${CSS}
</style></head>
<body>
  <header id="colapsado" class="${CLASSE_HEADER}">
    <div class="flex items-center">
      <button id="back" class="${CLASSE_BACK}"><span>‹</span></button>
      <img id="avatar" class="${CLASSE_AVATAR}" alt="" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" />
      <div class="flex flex-col gap-1">
        <div class="${CLASSE_LINHA_TITULO}">
          <h1 id="titulo" class="${CLASSE_TITULO}">Simplex Soluções</h1>
          <div id="dot" class="${CLASSE_DOT}"></div>
        </div>
      </div>
    </div>
    <div class="actions flex items-center gap-3">
      <button id="acao" class="${CLASSE_ACAO}"><span>×</span></button>
    </div>
  </header>
  <header id="expandido" class="${CLASSE_HEADER_EXP}">
    <h1 class="mt-4 text-2xl mb-1.5 font-medium text-w-on-brand">Olá!</h1>
    <p class="text-lg leading-normal text-w-on-brand opacity-80">Respondemos em minutos.</p>
  </header>
</body></html>`);
  await page.locator('#titulo').waitFor({ state: 'visible' });
  return page;
};

const caixa = async (page, id) =>
  page.$eval(id, el => {
    const r = el.getBoundingClientRect();
    return { w: Math.round(r.width), h: Math.round(r.height) };
  });

// ── 3.1 Celular: 375 px ─────────────────────────────────────────────────────
const mobile = await pagina(375);

checkAtLeast(
  'cabeçalho colapsado tem ao menos 56 px de altura',
  (await caixa(mobile, '#colapsado')).h,
  56
);
checkAtLeast(
  'cabeçalho expandido tem ao menos 96 px de altura',
  (await caixa(mobile, '#expandido')).h,
  96
);

const avatar = await caixa(mobile, '#avatar');
check('avatar mede 32x32', `${avatar.w}x${avatar.h}`, '32x32');
check(
  'avatar tem raio 6, não círculo',
  await mobile.$eval('#avatar', el => getComputedStyle(el).borderTopLeftRadius),
  '6px'
);

const alvos = await Promise.all(
  [
    ['#back', 'voltar'],
    ['#acao', 'ação do cabeçalho'],
  ].map(async ([id, rotulo]) => [rotulo, await caixa(mobile, id)])
);
alvos.forEach(([rotulo, b]) =>
  check(
    `em 375 px, ${rotulo} mede ao menos 44x44`,
    `${b.w >= 44}x${b.h >= 44}`,
    'truextrue'
  )
);

check(
  'o título usa a cor que o servidor calculou sobre a marca, não branco',
  await mobile.$eval('#titulo', el => getComputedStyle(el).color),
  'rgb(0, 0, 0)'
);
check(
  'o ponto de status também segue a cor sobre a marca',
  await mobile.$eval('#dot', el => getComputedStyle(el).backgroundColor),
  'rgb(0, 0, 0)'
);
check(
  'o cabeçalho é pintado com a marca da inbox',
  await mobile.$eval('#colapsado', el => getComputedStyle(el).backgroundColor),
  'rgb(255, 230, 0)'
);

// ── 3.2 Desktop: 1024 px ────────────────────────────────────────────────────
const desktop = await pagina(1024);
const acaoDesktop = await caixa(desktop, '#acao');
check(
  'acima de 768 px a ação encolhe para 40x40 — o alvo grande é do toque',
  `${acaoDesktop.w}x${acaoDesktop.h}`,
  '40x40'
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
process.exit(falhas.length ? 1 : 0);
