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

// ── `prefers-reduced-motion: reduce` — bloco 2.08 ────────────────────────────
//
// As cinco asserções acima medem a ANIMAÇÃO, e por isso rodam no contexto
// padrão, que é `no-preference`. As duas abaixo medem o oposto: que a mesma
// folha, lida por quem pediu ao sistema para parar de animar, não move nada.
//
// Elas existem porque o `SDK_CSS` tinha UM bloco `@media (prefers-reduced-
// motion: reduce)` e ele cobria só `.woot-teaser`. O holder e o lançador —
// que são o painel inteiro deslizando e um botão girando 45° — ficavam de
// fora, e o verificador dava 5/5 sem uma única asserção sobre o assunto.
//
// O contexto é NOVO, com `reducedMotion: 'reduce'`, e não `page.emulateMedia`
// no contexto já aberto: a emulação precisa valer desde o `setContent` para o
// navegador montar a folha já sob a preferência.
const ctxReduce = await browser.newContext({ reducedMotion: 'reduce' });
const pageReduce = await ctxReduce.newPage();

// As CINCO variantes do lançador, não uma: `transition` é declarada em oito
// regras do `SDK_CSS`, e a combinação `--expanded.--flat` é a mais específica
// delas (0,4,0). Medir só `.woot-widget-bubble` passaria com as combinações
// ainda animando — foi assim que o defeito sobreviveu até aqui.
await pageReduce.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0">
  <div id="cw-widget-holder" class="woot-widget-holder woot-elements--right">
    <iframe title="painel"></iframe>
  </div>
  <div id="cw-bubble-holder">
    <button id="b1" class="woot-widget-bubble woot-elements--right woot--close"></button>
    <button id="b2" class="woot-widget-bubble woot-elements--right"></button>
    <button id="b3" class="woot-widget-bubble woot-widget--expanded woot-elements--right"></button>
    <button id="b4" class="woot-widget-bubble woot-widget-bubble--flat woot--close woot-elements--right"></button>
    <button id="b5" class="woot-widget-bubble woot-widget--expanded woot-widget-bubble--flat woot-elements--right"></button>
    <div id="t1" class="woot-teaser woot-elements--right"></div>
  </div>
</body></html>`);
await pageReduce.locator('#cw-widget-holder').waitFor({ state: 'attached' });

// `transitionDuration` é uma LISTA — `0.3s, 0.1s, 0s, 0s` no lançador. Só
// serve como aceite se TODOS os termos forem zero, então a medida é o maior
// deles. O aceite admite "≤ 1 ms"; o corte é feito em milissegundos para que
// um futuro `0.001s` continue passando e um `0.01s` (que existe hoje na
// variante `--flat.--close`) continue reprovando.
const duracoes = await pageReduce.evaluate(() => {
  const maiorMs = sel => {
    const bruto = getComputedStyle(
      document.querySelector(sel)
    ).transitionDuration;
    return Math.max(...bruto.split(',').map(v => parseFloat(v) * 1000));
  };
  return {
    holder: maiorMs('#cw-widget-holder'),
    b1: maiorMs('#b1'),
    b2: maiorMs('#b2'),
    b3: maiorMs('#b3'),
    b4: maiorMs('#b4'),
    b5: maiorMs('#b5'),
    teaser: maiorMs('#t1'),
  };
});

console.log('        durações com reduce (ms) =', JSON.stringify(duracoes));

check(
  'com reduce, painel e lançador têm transição ≤ 1 ms',
  JSON.stringify(Object.entries(duracoes).filter(([, ms]) => ms > 1)),
  '[]'
);

// A segunda asserção não é a mesma medida escrita de outro jeito. A de cima lê
// a FOLHA em repouso; esta dispara a abertura de verdade e pergunta ao
// navegador o que ele MONTOU — é a mesma `getAnimations()` que o aceite do
// 1.07 nomeia, usada aqui para o caso contrário. Uma folha com
// `transition-duration: 0s` mas `transition-delay` sobrando ainda monta
// animação, e só esta pega isso.
const montadasComReduce = await pageReduce.evaluate(() => {
  const alvos = ['#cw-widget-holder', '#b1', '#b2', '#b3', '#b4', '#b5'];
  const montadas = [];
  alvos.forEach(sel => {
    const el = document.querySelector(sel);
    getComputedStyle(el).transform; // eslint-disable-line no-unused-expressions
    el.classList.add('woot--hide');
    el.getAnimations().forEach(a =>
      montadas.push(`${sel}:${a.transitionProperty || 'anim'}`)
    );
  });
  return montadas;
});

check(
  'com reduce, abrir e fechar não monta animação nenhuma',
  JSON.stringify(montadasComReduce),
  '[]'
);

await ctxReduce.close();
await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
