/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * BLOCO 3.18 — A PRECEDÊNCIA MEDIDA EM NAVEGADOR, com as duas fontes
 * preenchidas e DIVERGENTES.
 *
 * POR QUE ESTE ARQUIVO EXISTE, mesmo com 27 exemplos verdes em jsdom.
 *
 * O jsdom responde "que classe tem o elemento". Ninguém pergunta isso: a
 * pergunta é ONDE O LANÇADOR APARECE na página do cliente. Entre uma coisa e
 * outra está a cascata — e esta base já foi mordida três vezes por catch-all de
 * CSS com `!important` (`_base.scss:286` sabotando todo `<button>`, a skin
 * forçando `n-*` no escuro): componente certo, teste verde, tela errada.
 *
 * Aqui quem responde é o Chromium, e a asserção é geometria: `getBoundingClientRect`
 * do lançador contra a largura da janela. "Está à esquerda" é medido, não lido.
 *
 * O QUE É REAL AQUI, E O QUE É DUBLÊ
 *
 *   · REAL — o `SDK_CSS` extraído do arquivo de produção, sem reescrita;
 *   · REAL — o DOM que o `IFrameHelper` monta: as MESMAS classes, na mesma
 *     ordem, e o `--w-offset-*` no `#cw-bubble-holder` como o `applyAppearance`
 *     o escreve;
 *   · DUBLÊ — nada de rede: as três matrizes são estados finais já resolvidos
 *     pela regra de precedência, e cada uma tem o par (banco, site) explícito.
 *
 * Extensão `.check.mjs` de propósito: fora do `include` do vitest, roda com
 * `node`, NÃO carrega `playwright.config.js` e portanto não sobe `webServer`
 * nem toca nas portas fixas compartilhadas.
 *
 *   node app/javascript/sdk/specs/browser/appearance-precedence.check.mjs
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
  const ok = String(actual) === String(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

const LARGURA = 1280;
const ALTURA = 800;

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: LARGURA, height: ALTURA },
});

/**
 * Monta o lançador exatamente como `IFrameHelper.onLoad` + `createBubbleIcon`
 * o montam, para o `position` efetivo e o offset informados.
 */
const montar = async ({ position, offset }) => {
  const estilo = offset
    ? `--w-offset-x:${offset.x}px; --w-offset-y:${offset.y}px;`
    : '';

  await page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0;background:#fff">
  <div id="cw-widget-holder"
       class="woot-widget-holder woot--hide woot-elements--${position}"></div>
  <div id="cw-bubble-holder" class="woot--bubble-holder"
       style="--w-brand:#009ce0; --w-on-brand:#000000; ${estilo}">
    <button id="lancador" class="woot-widget-bubble woot-elements--${position}">
      <svg width="24" height="24" viewBox="0 0 240 240" fill="none"></svg>
    </button>
    <div class="woot-teaser woot-teaser--visivel woot-elements--${position}">
      <span>Posso ajudar?</span>
    </div>
  </div>
</body></html>`);

  return page.evaluate(() => {
    const lancador = document.getElementById('lancador');
    const teaser = document.querySelector('.woot-teaser');
    const r = lancador.getBoundingClientRect();
    const t = teaser.getBoundingClientRect();
    return {
      esquerda: Math.round(r.left),
      direita: Math.round(window.innerWidth - r.right),
      fundo: Math.round(window.innerHeight - r.bottom),
      teaserFundo: Math.round(window.innerHeight - t.bottom),
      teaserDireita: Math.round(window.innerWidth - t.right),
      // `position: fixed` só vale se o elemento for de fato fixo; um `static`
      // herdado poria o lançador no fluxo do documento do cliente.
      posicao: getComputedStyle(lancador).position,
    };
  });
};

console.log(
  '\n── 1. site MUDO, banco diz `left` ───────────────────────────────────────'
);
console.log(
  '   (é o caso que estava quebrado: o host caía no literal `right`)\n'
);
const bancoEsquerda = await montar({ position: 'left' });
check('lançador a 20px da borda ESQUERDA', bancoEsquerda.esquerda, 20);
check('e longe da direita (1280 - 20 - 64)', bancoEsquerda.direita, 1196);
check(
  'fixo, fora do fluxo da página do cliente',
  bancoEsquerda.posicao,
  'fixed'
);

console.log(
  '\n── 2. as duas fontes preenchidas e DIVERGENTES ──────────────────────────'
);
console.log('   banco = `left`, chatwootSettings.position = `right`\n');
console.log('   → a regra de precedência resolveu para `right`; medindo:\n');
const siteVence = await montar({ position: 'right' });
check('lançador a 20px da borda DIREITA', siteVence.direita, 20);
check('e NÃO à esquerda', siteVence.esquerda, 1196);

console.log(
  '\n── 3. offset_x/offset_y do banco (o par que o site não disputa) ─────────\n'
);
const semOffset = await montar({ position: 'right' });
check('sem offset: 20px da direita', semOffset.direita, 20);
check('sem offset: 20px do fundo', semOffset.fundo, 20);
check('sem offset: teaser a 96px do fundo', semOffset.teaserFundo, 96);

const comOffset = await montar({ position: 'right', offset: { x: 40, y: 24 } });
check('offset_x=40: 60px da direita', comOffset.direita, 60);
check('offset_y=24: 44px do fundo', comOffset.fundo, 44);
check(
  'o teaser acompanha o lançador: 120px do fundo',
  comOffset.teaserFundo,
  120
);
check('e também na horizontal: 60px da direita', comOffset.teaserDireita, 60);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} verificações ok`
);
if (falhas.length) {
  console.error(`FALHOU: ${falhas.map(f => f.name).join(' | ')}`);
  process.exit(1);
}
