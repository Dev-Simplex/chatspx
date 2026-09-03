/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e
   colada no relatório do bloco. Não é log esquecido em código de produção,
   que é o que a regra existe para pegar. */
/**
 * Mecanismo de aceite do bloco 1.07 — segunda metade.
 *
 * ACEITE (§2.2): "`getAnimations()` na abertura não devolve `linear` em
 * `transform`".
 *
 * O aceite nomeia a API de propósito: `getAnimations()` devolve a transição que
 * o navegador REALMENTE montou, com o easing já resolvido. Ler o CSS não bastaria
 * — uma `var()` não declarada no host cai para o valor inicial e o easing volta a
 * ser o padrão sem que nada no texto do CSS mude. É o risco real aqui, porque as
 * três curvas moram em `_tokens.scss`, que só é carregado DENTRO do iframe,
 * enquanto o holder e o lançador vivem no documento do host.
 *
 *   node app/javascript/sdk/specs/browser/open-animation.check.mjs
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

// O holder é montado como o SDK o monta: com as classes reais e o id real, que é
// onde as curvas são declaradas.
await page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0">
  <div id="cw-widget-holder"
       class="woot-widget-holder woot-elements--right woot--hide">
    <iframe title="painel"></iframe>
  </div>
  <div id="cw-bubble-holder">
    <button class="woot-widget-bubble woot-elements--right woot--close"></button>
  </div>
</body></html>`);

// `attached`, não `visible`: o holder nasce com `woot--hide`, que é
// `visibility: hidden` — esperar visibilidade aqui seria esperar para sempre. O
// que interessa é ele existir no DOM para podermos medir a ABERTURA.
await page.locator('#cw-widget-holder').waitFor({ state: 'attached' });

// ── As curvas chegam ao host? ────────────────────────────────────────────────
const curvas = await page.evaluate(() => {
  const s = getComputedStyle(document.getElementById('cw-widget-holder'));
  return {
    standard: s.getPropertyValue('--w-ease-standard').trim(),
    enter: s.getPropertyValue('--w-ease-enter').trim(),
    exit: s.getPropertyValue('--w-ease-exit').trim(),
  };
});
check(
  'as três curvas da casa estão declaradas no host',
  JSON.stringify(curvas),
  JSON.stringify({
    standard: 'cubic-bezier(0.2, 0, 0, 1)',
    enter: 'cubic-bezier(0.05, 0.7, 0.1, 1)',
    exit: 'cubic-bezier(0.3, 0, 0.8, 0.15)',
  })
);

// ── A abertura, medida por getAnimations() ───────────────────────────────────
// Dispara a transição removendo `woot--hide` e lê o que o navegador montou. O
// `getComputedStyle` antes do toggle força o estado inicial a ser calculado —
// sem isso o navegador pode colapsar as duas mudanças e não montar transição.
const abertura = await page.evaluate(() => {
  const el = document.getElementById('cw-widget-holder');
  getComputedStyle(el).transform; // eslint-disable-line no-unused-expressions
  el.classList.remove('woot--hide');
  return el.getAnimations().map(a => ({
    prop: a.transitionProperty || null,
    easing: a.effect.getComputedTiming().easing,
  }));
});

console.log('        getAnimations() =', JSON.stringify(abertura));

const transformAnims = abertura.filter(a => a.prop === 'transform');
check(
  'a abertura monta transição de transform',
  String(transformAnims.length > 0),
  'true'
);
// A asserção do aceite, na forma que ele pede.
check(
  'nenhuma transição de transform com easing linear',
  JSON.stringify(transformAnims.filter(a => a.easing === 'linear')),
  '[]'
);
// E o valor esperado, não só "não é linear": o easing tem de ser a curva de
// entrada da casa. "não linear" passaria com `ease`, que não é a nossa.
check(
  'o transform da abertura usa a curva de ENTRADA',
  transformAnims.map(a => a.easing).join(','),
  'cubic-bezier(0.05, 0.7, 0.1, 1)'
);

// ── O fechamento usa a curva de saída ───────────────────────────────────────
const fechamento = await page.evaluate(() => {
  const el = document.querySelector('.woot-widget-bubble');
  getComputedStyle(el).transform; // eslint-disable-line no-unused-expressions
  el.classList.add('woot--hide');
  return el
    .getAnimations()
    .filter(a => a.transitionProperty === 'transform')
    .map(a => a.effect.getComputedTiming().easing);
});
check(
  'o transform de saída do lançador usa a curva de SAÍDA',
  fechamento.join(','),
  'cubic-bezier(0.3, 0, 0.8, 0.15)'
);

await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
