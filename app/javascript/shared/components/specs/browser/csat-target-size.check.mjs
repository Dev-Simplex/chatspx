/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e colada
   no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 4.10 — a asserção "alvos 44×44" (SC 2.5.8).
 *
 * POR QUE NÃO É UM `.spec.js`: jsdom não faz layout. `getBoundingClientRect()`
 * lá devolve 0×0 para tudo, então um teste de tamanho de alvo em jsdom fica
 * verde com o defeito vivo — que é exatamente a classe de falso verde que esta
 * onda existe para não repetir.
 *
 * E há um modo de falha que só o motor revela: `min-width`/`min-height` NÃO
 * fazem nada num elemento `display: inline`. O `<button>` do CSAT ganhou
 * `inline-flex`; se alguém trocar por um utilitário que volte a `inline`, o
 * alvo desmancha em silêncio e o teste de marcação continua passando.
 *
 * As classes e as regras NÃO são escritas aqui: são EXTRAÍDAS dos dois SFCs. Se
 * alguém mudar o componente, este verificador mede o novo — não continua
 * medindo uma fixture que só existe dentro dele.
 *
 *   node app/javascript/shared/components/specs/browser/csat-target-size.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';

const repoRoot = new URL('../../../../../', import.meta.url).pathname;
const ALVO_MINIMO = 44;

const estrelas = readFileSync(
  new URL('../../StarRating.vue', import.meta.url),
  'utf8'
);
const csat = readFileSync(
  new URL('../../CustomerSatisfaction.vue', import.meta.url),
  'utf8'
);

const results = [];
const check = (name, ok, detalhe) => {
  results.push({ name, ok });
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}\n        ${detalhe}`);
};

// ── 1. Extrai as classes reais dos dois botões ───────────────────────────────
const classeEstrela = estrelas.match(/class="(star-rating__opcao[^"]*)"/)?.[1];
const applyEmoji = csat
  .match(/\.emoji-button \{\s*@apply ([^;]+);/)?.[1]
  .replace(/\s+/g, ' ')
  .trim();

if (!classeEstrela || !applyEmoji) {
  console.error('FALHA: não localizei as classes dos botões nos SFCs');
  process.exit(1);
}

// As regras de tamanho vêm do bloco <style> de cada componente, lidas do arquivo.
const regraDe = (fonte, seletor) => {
  const bloco = fonte.match(
    new RegExp(`${seletor}\\s*\\{([\\s\\S]*?)\\n\\s*(?:&|\\})`)
  )?.[1];
  const min = (bloco ?? '').match(/min-(width|height):\s*(\d+)px/g) || [];
  return min.join('; ');
};
const regraEstrela = regraDe(estrelas, '\\.star-rating__opcao');
const regraEmoji = regraDe(csat, '\\.emoji-button');

check(
  'a regra de 44px está no SFC das estrelas',
  /min-width:\s*44px/.test(regraEstrela) &&
    /min-height:\s*44px/.test(regraEstrela),
  `extraído: ${regraEstrela || '(nada)'}`
);
check(
  'a regra de 44px está no SFC do CSAT',
  /min-width:\s*44px/.test(regraEmoji) && /min-height:\s*44px/.test(regraEmoji),
  `extraído: ${regraEmoji || '(nada)'}`
);

// ── 2. Compila as utilities do projeto — o CSS de verdade ────────────────────
const dir = mkdtempSync(join(tmpdir(), 'csat-target-'));
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

// ── 3. Mede no navegador ─────────────────────────────────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

await page.setContent(`<!doctype html>
<html><head>
<style>${CSS}</style>
<style>
  .star-rating__opcao { ${regraEstrela.replace(/;\s*$/, '')}; }
  .emoji-button { ${regraEmoji.replace(/;\s*$/, '')}; }
</style>
</head>
<body style="margin:0">
  <div role="radiogroup" class="flex justify-center py-5 px-4 gap-1">
    <button type="button" role="radio" id="estrela" class="${classeEstrela}">
      <span class="i-ri-star-line text-2xl" aria-hidden="true"></span>
    </button>
  </div>
  <div role="radiogroup" class="ratings flex justify-around py-5 px-4">
    <button type="button" role="radio" id="emoji" class="emoji-button ${applyEmoji}">
      <span aria-hidden="true">&#128542;</span>
    </button>
  </div>
</body></html>`);

const medir = async sel => {
  const el = page.locator(sel);
  await el.waitFor({ state: 'visible' });
  return el.evaluate(node => {
    const r = node.getBoundingClientRect();
    return {
      w: Math.round(r.width),
      h: Math.round(r.height),
      display: getComputedStyle(node).display,
      minW: getComputedStyle(node).minWidth,
      minH: getComputedStyle(node).minHeight,
    };
  });
};

for (const [nome, seletor] of [
  ['estrela', '#estrela'],
  ['emoji', '#emoji'],
]) {
  // eslint-disable-next-line no-await-in-loop -- são dois; medir em paralelo
  // embaralharia a ordem da saída, que é o resultado que alguém vai ler.
  const m = await medir(seletor);

  check(
    `${nome}: alvo renderizado >= ${ALVO_MINIMO}x${ALVO_MINIMO} (SC 2.5.8)`,
    m.w >= ALVO_MINIMO && m.h >= ALVO_MINIMO,
    `medido ${m.w}x${m.h}px`
  );
  check(
    `${nome}: display honra min-width/min-height (nao e 'inline')`,
    m.display !== 'inline',
    `display computado = ${m.display}; min-width=${m.minW} min-height=${m.minH}`
  );
}

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
