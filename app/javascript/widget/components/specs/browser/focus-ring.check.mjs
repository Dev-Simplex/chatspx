/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e
   colada no relatório do bloco. Não é log esquecido em código de produção,
   que é o que a regra existe para pegar. */
/**
 * Mecanismo de aceite do bloco 1.06 — a terceira asserção: `outline-color` não
 * transparente, e anel de foco que de fato desenha.
 *
 * Por que não é um `.spec.js`: as duas coisas que interessam aqui só existem
 * depois do Tailwind compilar e do navegador resolver a cascade.
 *
 *   1. `shadow-focus` era usada em `ChatInputWrap.vue` e não existia em config
 *      nenhum. Tailwind descarta classe desconhecida em SILÊNCIO — nada quebra,
 *      o anel simplesmente não é pintado. Só o CSS compilado revela.
 *   2. `outline-none` do Tailwind gera `outline: 2px solid transparent`. Um anel
 *      de 2px transparente passa em qualquer teste de marcação e é invisível
 *      para quem navega por teclado. Só `getComputedStyle` revela.
 *
 * As classes NÃO são escritas aqui: são extraídas de `ChatInputWrap.vue`. Se
 * alguém trocar as classes do composer, este teste mede as novas — e não
 * continua medindo uma fixture que só existe dentro dele.
 *
 *   node app/javascript/widget/components/specs/browser/focus-ring.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';

const repoRoot = new URL('../../../../../../', import.meta.url).pathname;
const componente = readFileSync(
  new URL('../../ChatInputWrap.vue', import.meta.url),
  'utf8'
);

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// ── 1. Extrai do componente as classes reais do contêiner do composer ────────
const classeBase = componente.match(/class="(items-center flex[^"]*)"/);
const classeFoco = componente.match(/'([^']*shadow-focus[^']*)':\s*isFocused/);
if (!classeBase || !classeFoco) {
  console.error(
    'FALHA: não localizei as classes do composer em ChatInputWrap.vue'
  );
  process.exit(1);
}
const CONTAINER = `${classeBase[1]} ${classeFoco[1]}`;
const TEXTAREA = (componente.match(/@apply (border-none outline-[^;]*);/) ||
  [])[1];
if (!TEXTAREA) {
  console.error('FALHA: não localizei o @apply do textarea');
  process.exit(1);
}

// O composer não pode voltar a usar `outline-none`: é o utilitário que pinta o
// anel transparente. Asserção textual, sobre o arquivo real — medindo o que é
// APLICADO. Comentários saem antes: o componente explica em prosa por que
// `outline-none` foi trocado, e citar o nome do utilitário numa explicação não
// pinta anel nenhum.
const semComentarios = componente
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^\s*\/\/.*$/gm, '');
check(
  'ChatInputWrap não aplica outline-none em classe nenhuma',
  String(/\boutline-none\b/.test(semComentarios)),
  'false'
);

// ── 2. Compila as utilities do projeto — o CSS de verdade, não um recorte ────
const dir = mkdtempSync(join(tmpdir(), 'focus-ring-'));
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(inCss, '@tailwind utilities;\n');
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.config.js',
    '-i',
    inCss,
    '-o',
    outCss,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(outCss, 'utf8');

check(
  '.shadow-focus existe no CSS compilado',
  String(/\.shadow-focus\s*\{/.test(CSS)),
  'true'
);

// ── 3. Mede no navegador ─────────────────────────────────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

// Os tokens de foco entram como `_tokens.scss` os declara no widget.
await page.setContent(`<!doctype html>
<html><head><style>
  :root {
    --w-focus-ring-color: #1d824a;
    --w-focus-ring-width: 2px;
    --w-focus-ring-offset: 2px;
  }
  ${CSS}
</style></head>
<body style="margin:0">
  <div id="container" class="${CONTAINER}">
    <textarea id="composer" class="${TEXTAREA}"></textarea>
  </div>
</body></html>`);

const container = page.locator('#container');
const composer = page.locator('#composer');
await composer.waitFor({ state: 'visible' });

// O contêiner só recebe a classe de foco quando `isFocused` é true no Vue; aqui
// ela já está aplicada, porque o que se mede é se ela DESENHA.
const sombra = await container.evaluate(el => getComputedStyle(el).boxShadow);
check(
  'o anel de foco desenha (box-shadow não é "none")',
  String(sombra !== 'none' && sombra !== ''),
  'true'
);
check(
  'o anel usa a cor do token, não uma cor própria',
  String(sombra.includes('rgb(29, 130, 74)')),
  'true'
);

await composer.focus();
await page.waitForFunction(() => document.activeElement?.id === 'composer');

// A asserção do aceite: nenhum elemento do composer pode ter anel de largura
// visível E cor transparente. `outline-0` zera a largura; `outline-none` deixava
// 2px transparentes, que é o defeito.
const anelFantasma = await page.evaluate(() =>
  [...document.querySelectorAll('#container, #composer')]
    .map(el => {
      const s = getComputedStyle(el);
      return {
        id: el.id,
        style: s.outlineStyle,
        width: s.outlineWidth,
        color: s.outlineColor,
      };
    })
    .filter(
      o =>
        o.style !== 'none' &&
        parseFloat(o.width) > 0 &&
        (o.color === 'rgba(0, 0, 0, 0)' || o.color === 'transparent')
    )
);
check(
  'nenhum anel com largura > 0 e cor transparente',
  JSON.stringify(anelFantasma),
  '[]'
);

await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
