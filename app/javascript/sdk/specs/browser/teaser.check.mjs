/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * Aceites do teaser que dependem de CASCADE — bloco 4.06, §C.2 do plano 22.
 *
 *   5. alvo de dispensa ≥ 32×32 (o do Olark tem 9,8×9,8)
 *   7. sob `prefers-reduced-motion`, aparece sem animação
 *  10. Discreto é o Chamativo com foto e chip ocultos POR CSS
 *
 * E a ancoragem do enunciado do bloco: **"o teaser, no host, AO LADO do
 * lançador"**.
 *
 * jsdom não serve para nenhum dos quatro: não calcula caixa, não resolve media
 * query e não aplica folha de estilo. O spec em jsdom (`specs/teaser.spec.js`)
 * cobre gatilho, cookie e montagem; este cobre o que só o navegador sabe.
 *
 * ⚠️ ESTE ARQUIVO MONTA O COMPONENTE DE VERDADE, E ANTES NÃO MONTAVA.
 *
 * Ele escrevia o cartão à mão no HTML da página — incluindo a classe
 * `woot-elements--right`, que `teaser.js` NUNCA aplicava. O verificador media um
 * DOM que o SDK não produz, então media a própria fixture: por isso as sete
 * asserções abaixo passavam enquanto o teaser nascia 980 px longe do lançador,
 * na quina oposta. Uma asserção só vale o que vale a origem do sujeito.
 *
 * Agora `teaser.js` é empacotado com o Vite (grafo real: `cookieHelpers`,
 * `tracking/approach`, `js-cookie`) e executado na página. O cartão medido é o
 * que `montarTeaser` cria, com o `className` que ele mesmo escreve.
 *
 * DUAS CONSEQUÊNCIAS DE MONTAR O COMPONENTE DE VERDADE, e as duas são de
 * ambiente, não de estilo:
 *   · o gatilho composto (8 s E 30 %) passa a valer aqui. `page.clock` adianta o
 *     relógio em vez de esperar — 4 montagens × 8 s seriam 32 s de espera real.
 *   · a dispensa é um COOKIE, e `page.setContent` roda em origem opaca, onde
 *     `document.cookie` lança `SecurityError`. Por isso a página é servida por
 *     `page.route` numa origem `http://` de mentira: sem porta, sem servidor e
 *     sem disputar as portas 3038/3999/8899 do coordenador.
 *
 * ⚠️ NÃO USA O HARNESS DE PORTA FIXA — `chromium.launch()` direto, sem
 * `playwright.config.js` e sem `webServer`.
 *
 *   node app/javascript/sdk/specs/browser/teaser.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { build } from 'vite';

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

const fonte = readFileSync(new URL('../../sdk.js', import.meta.url), 'utf8');
const CSS = fonte.match(/export const SDK_CSS = `([\s\S]*?)\n`;/)[1];

// A documentação foi movida para FORA da string no bloco 4.06 — comentário
// dentro de string é dado, e era baixado por todo visitante. Se voltar, volta o
// peso: esta asserção é a guarda.
check(
  'o SDK_CSS não carrega comentário (eles custam bytes de rede)',
  String((CSS.match(/\/\*/g) || []).length),
  '0'
);

// O MÓDULO REAL, empacotado. `write: false` mantém tudo em memória: o
// verificador não escreve em `public/` nem depende de um build anterior.
const entrada = new URL('../../teaser.js', import.meta.url).pathname;
const saida = await build({
  root: new URL('../../../../../', import.meta.url).pathname,
  logLevel: 'error',
  configFile: false,
  build: {
    write: false,
    lib: {
      entry: entrada,
      formats: ['iife'],
      name: 'wootTeaser',
      fileName: 't',
    },
  },
});
const BUNDLE = saida[0].output[0].code;

// O lançador REAL ao lado do qual o teaser tem de nascer: mesmas classes que
// `createBubbleHolder` e `createBubbleIcon` produzem no host.
const HTML = `<!doctype html>
<html lang="pt-BR"><head><title>t</title><style>${CSS}</style></head>
<body style="margin:0;height:3000px">
  <div id="cw-bubble-holder" class="woot--bubble-holder">
    <button id="lancador" class="woot-widget-bubble woot-elements--right"></button>
  </div>
  <script>${BUNDLE}</script>
</body></html>`;

const browser = await chromium.launch();

/**
 * Monta o teaser DE VERDADE e mede. `position` chega como o host o entrega.
 */
const medir = async (nivel, opcoes = {}, position = 'right') => {
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    ...opcoes,
  });
  const page = await ctx.newPage();
  await page.clock.install();
  await page.route('**/*', rota =>
    rota.fulfill({ contentType: 'text/html; charset=utf-8', body: HTML })
  );
  await page.goto('http://teaser.test/');

  await page.evaluate(
    ([nivelAtual, lado]) => {
      window.wootTeaser.montarTeaser({
        holder: document.getElementById('cw-bubble-holder'),
        canal: {
          teaserText: 'Fale com a gente',
          replyTime: 'Responde em minutos',
        },
        nivel: nivelAtual,
        position: lado,
      });
      // As DUAS condições do gatilho composto: rolagem primeiro, relógio depois.
      window.scrollTo(0, 1500);
      window.dispatchEvent(new Event('scroll'));
    },
    [nivel, position]
  );

  await page.clock.fastForward(9000);
  await page.locator('.woot-teaser').waitFor({ timeout: 5000 });

  const dados = await page.evaluate(() => {
    const q = s => document.querySelector(s);
    const cx = el => {
      const r = el.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height) };
    };
    const cartao = q('.woot-teaser');
    const rc = cartao.getBoundingClientRect();
    const rl = q('#lancador').getBoundingClientRect();
    return {
      className: cartao.className,
      fechar: cx(q('.woot-teaser__fechar')),
      cartao: cx(cartao),
      fotoVisivel: getComputedStyle(q('.woot-teaser__foto')).display !== 'none',
      chipVisivel: getComputedStyle(q('.woot-teaser__chip')).display !== 'none',
      transicao: getComputedStyle(cartao).transitionDuration,
      // Distância entre as quinas do MESMO lado. É o número do enunciado:
      // "ao lado do lançador".
      distanciaDireita: Math.round(Math.abs(rc.right - rl.right)),
      // A quina que o cartão de fato encosta, para o caso `left`: o recuo
      // declarado nas regras de âncora é 20px dos dois lados.
      recuoEsquerdo: Math.round(rc.left),
    };
  });
  await ctx.close();
  return dados;
};

// ── Ancoragem — o enunciado do bloco ────────────────────────────────────────
const bold = await medir('bold');
check(
  'o cartão que o SDK cria traz a classe de ancoragem',
  String(bold.className.includes('woot-elements--right')),
  'true'
);
check(
  'e ela vem do componente, não da fixture (className real)',
  bold.className,
  'woot-teaser woot-teaser--bold woot-elements--right woot-teaser--visivel'
);
// 20px é o recuo da quina que as duas regras de âncora declaram; o lançador usa
// o mesmo. Mesmo lado ⇒ as bordas direitas coincidem.
check(
  'o teaser nasce AO LADO do lançador, não no canto oposto (quina direita)',
  String(bold.distanciaDireita),
  '0'
);

const esquerda = await medir('bold', {}, 'left');
check(
  'com position=left o cartão acompanha o lançador para a esquerda',
  String(esquerda.className.includes('woot-elements--left')),
  'true'
);
check(
  'e a âncora da esquerda é a única no cartão (nunca as duas)',
  String(esquerda.className.includes('woot-elements--right')),
  'false'
);
// A classe é a CAUSA; este é o EFEITO, e é o que o visitante vê. Sem ele o
// verificador voltaria a acreditar num `className` — que foi exatamente como o
// defeito passou da primeira vez.
check(
  'e o cartão da esquerda encosta na quina esquerda (recuo de 20px)',
  String(esquerda.recuoEsquerdo),
  '20'
);

// ── Aceite 5 ────────────────────────────────────────────────────────────────
check(
  'aceite 5 — alvo de dispensa ≥ 32×32',
  String(bold.fechar.w >= 32 && bold.fechar.h >= 32),
  'true'
);
check(
  'e o alvo medido é 44×44 (o do Olark tem 9,8×9,8)',
  `${bold.fechar.w}x${bold.fechar.h}`,
  '44x44'
);

// ── Aceite 10 ───────────────────────────────────────────────────────────────
const discreet = await medir('discreet');
check('Chamativo mostra a foto', String(bold.fotoVisivel), 'true');
check('Chamativo mostra o chip', String(bold.chipVisivel), 'true');
check(
  'Discreto ESCONDE a foto (por CSS)',
  String(discreet.fotoVisivel),
  'false'
);
check(
  'Discreto ESCONDE o chip (por CSS)',
  String(discreet.chipVisivel),
  'false'
);
check(
  'e o Discreto fica mais estreito que o Chamativo em altura',
  String(discreet.cartao.h < bold.cartao.h),
  'true'
);

// ── Aceite 7 ────────────────────────────────────────────────────────────────
const reduzido = await medir('bold', { reducedMotion: 'reduce' });
check(
  'aceite 7 — com prefers-reduced-motion a transição é 0s',
  reduzido.transicao,
  '0s'
);
check(
  'e sem a preferência ela existe (250ms de entrada)',
  bold.transicao.startsWith('0.25s') ? 'tem' : bold.transicao,
  'tem'
);

await browser.close();
const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
