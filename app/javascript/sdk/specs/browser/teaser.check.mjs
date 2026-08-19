/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * Aceites do teaser que dependem de CASCADE — bloco 4.06, §C.2 do plano 22.
 *
 *   5. alvo de dispensa ≥ 32×32 (o do Olark tem 9,8×9,8)
 *   7. sob `prefers-reduced-motion`, aparece sem animação
 *  10. Discreto é o Chamativo com foto e chip ocultos POR CSS
 *
 * jsdom não serve para nenhum dos três: não calcula caixa, não resolve media
 * query e não aplica folha de estilo. O spec em jsdom (`specs/teaser.spec.js`)
 * cobre gatilho, cookie e montagem; este cobre o que só o navegador sabe.
 *
 * ⚠️ NÃO USA O HARNESS DE PORTA FIXA — `chromium.launch()` direto, sem
 * `playwright.config.js` e sem `webServer`. As portas 3038/3999/8899 estão sob
 * tranca do coordenador.
 *
 *   node app/javascript/sdk/specs/browser/teaser.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';

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

const pagina = nivel => `<!doctype html>
<html lang="pt-BR"><head><title>t</title><style>${CSS}</style></head>
<body style="margin:0;height:3000px">
  <div id="cw-bubble-holder">
    <div class="woot-teaser woot-teaser--${nivel} woot-teaser--visivel woot-elements--right" role="status">
      <img class="woot-teaser__foto" alt="" src="data:image/gif;base64,R0lGODlhAQABAAAAACw="/>
      <div class="woot-teaser__corpo">
        <p class="woot-teaser__texto">Fale com a gente</p>
        <span class="woot-teaser__chip">Responde em minutos</span>
      </div>
      <button class="woot-teaser__fechar" type="button" aria-label="Dispensar">×</button>
    </div>
  </div>
</body></html>`;

const browser = await chromium.launch();

const medir = async (nivel, opcoes = {}) => {
  const ctx = await browser.newContext(opcoes);
  const page = await ctx.newPage();
  await page.setContent(pagina(nivel));
  await page.locator('.woot-teaser').waitFor();
  const dados = await page.evaluate(() => {
    const q = s => document.querySelector(s);
    const cx = el => {
      const r = el.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height) };
    };
    return {
      fechar: cx(q('.woot-teaser__fechar')),
      cartao: cx(q('.woot-teaser')),
      fotoVisivel: getComputedStyle(q('.woot-teaser__foto')).display !== 'none',
      chipVisivel: getComputedStyle(q('.woot-teaser__chip')).display !== 'none',
      transicao: getComputedStyle(q('.woot-teaser')).transitionDuration,
    };
  });
  await ctx.close();
  return dados;
};

// ── Aceite 5 ────────────────────────────────────────────────────────────────
const bold = await medir('bold');
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
check('Discreto ESCONDE a foto (por CSS)', String(discreet.fotoVisivel), 'false');
check('Discreto ESCONDE o chip (por CSS)', String(discreet.chipVisivel), 'false');
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
console.log(`\n${results.length - failed.length}/${results.length} asserções ok`);
process.exit(failed.length ? 1 : 0);
