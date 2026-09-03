/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 2.09 — a geometria, medida no navegador.
 *
 * ACEITE (§2.2): "767 px fullscreen, 768 flutuante, sem ambiguidade".
 *
 * O `mobileBreakpoint.spec.js` prova que os NÚMEROS ficaram coerentes lendo o
 * arquivo. Isso não prova que a página se comporta: media query só vira
 * geometria depois que um navegador resolve a cascade. Aqui o CSS real do SDK é
 * injetado e as duas larguras de fronteira são medidas — 767 e 768, os dois
 * pixels onde o defeito morava.
 *
 *   node app/javascript/sdk/specs/browser/mobile-breakpoint.check.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
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

// O CSS sai do arquivo de produção, não de uma cópia: é a template string que o
// SDK injeta na página do cliente.
const sdkFonte = readFileSync(join(repoRoot, 'app/javascript/sdk/sdk.js'), 'utf8');
const SDK_CSS = /export const SDK_CSS = `([\s\S]*?)`;/.exec(sdkFonte)?.[1];
if (!SDK_CSS) throw new Error('não localizei SDK_CSS em sdk.js');

const browser = await chromium.launch();

const medirEm = async largura => {
  const page = await browser.newPage({ viewport: { width: largura, height: 800 } });
  await page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0">
  <div class="woot-widget-holder woot-elements--right" id="holder">
    <div style="height:100px">painel</div>
  </div>
</body></html>`);
  await page.locator('#holder').waitFor();
  const medida = await page.$eval('#holder', el => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return {
      width: Math.round(r.width),
      radius: s.borderTopLeftRadius,
      bottom: s.bottom,
    };
  });
  await page.close();
  return medida;
};

// ── 767: o último pixel de tela cheia ───────────────────────────────────────
const em767 = await medirEm(767);
check('em 767 px o painel ocupa a largura inteira', String(em767.width), '767');
check('em 767 px não há canto arredondado — é tela cheia', em767.radius, '0px');

// ── 768: o primeiro pixel flutuante ─────────────────────────────────────────
const em768 = await medirEm(768);
check('em 768 px o painel é flutuante, com largura fixa', String(em768.width), '400');
check('em 768 px o painel tem canto de 16', em768.radius, '16px');
check('em 768 px o painel descola do rodapé', em768.bottom, '104px');

// ── A fronteira não pode ter estado duplo ───────────────────────────────────
// Antes, `min-width: 667px` e `max-width: 667px` casavam AMBAS em 667: o pixel
// tinha as duas geometrias e vencia a ordem do arquivo. Agora as faixas são
// disjuntas, e é isso que estas duas medidas provam ao serem DIFERENTES.
check(
  'os dois pixels de fronteira têm geometrias distintas',
  String(em767.width !== em768.width && em767.radius !== em768.radius),
  'true'
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(`\n${results.length - falhas.length}/${results.length} asserções passaram`);
process.exit(falhas.length ? 1 : 0);
