/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e
   colada no relatório do bloco. Não é log esquecido em código de produção,
   que é o que a regra existe para pegar. */
/**
 * Mecanismo de aceite do bloco 1.05 — a armadilha do `:hover` verde.
 *
 * ACEITE (§2.2): "Launcher em `#009CE0` continua `rgb(0,156,224)` **em `:hover`**".
 *
 * Por que este arquivo não é um `.spec.js` do vitest: o defeito que ele persegue
 * é de CASCADE. `.woot-widget-bubble:hover` tinha `#2dc46f` cravado, e o único
 * motivo de isso não aparecer na tela era um `style.background` inline que vencia
 * a folha. jsdom não resolve `:hover` nem calcula cascade de folha injetada — um
 * teste em jsdom daria verde com o defeito vivo, que é precisamente a falha que
 * esta onda existe para não repetir. Aqui roda Chromium de verdade, com
 * `getComputedStyle` de verdade, e o mouse de verdade em cima do elemento.
 *
 * Extensão `.check.mjs` de propósito: o `include` do vitest é
 * `app/**\/*.{test,spec}.?(c|m)[jt]s?(x)`, então este arquivo não é coletado por
 * ele. Roda com `node`, e NÃO carrega `playwright.config.js` — logo não sobe
 * `webServer` nenhum e não toca nas portas fixas 3038/3999/8899, que são
 * compartilhadas com as outras trilhas.
 *
 *   node app/javascript/sdk/specs/browser/launcher-hover.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';

const BRAND = '#009CE0';
const EXPECTED = 'rgb(0, 156, 224)';
// `--w-on-brand` para `#009CE0` é `#000000` (L = 0,2916 > 0,17913). É o valor
// que o serviço Ruby do 1.02 calcula; aqui ele entra como o servidor o emitiria.
const ON_BRAND = '#000000';

const source = readFileSync(new URL('../../sdk.js', import.meta.url), 'utf8');
const match = source.match(/export const SDK_CSS = `([\s\S]*?)\n`;/);
if (!match) {
  console.error('FALHA: não consegui extrair SDK_CSS de sdk.js');
  process.exit(1);
}
const SDK_CSS = match[1];

// O literal que este bloco mata. Se ele reaparecer no CSS, o teste tem de
// falhar mesmo que a cor medida esteja certa por outro motivo.
const GREEN = '#2dc46f';

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, actual, expected, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

const browser = await chromium.launch();
const page = await browser.newPage();

// Reproduz o que o SDK monta no documento do host: o holder carrega os tokens
// que `applyWidgetTokens` escreve, e o lançador é filho dele. Nada de estilo
// inline no botão — a ausência dele é o bloco 1.05.
await page.setContent(`<!doctype html>
<html><head><style>${SDK_CSS}</style></head>
<body style="margin:0">
  <div id="cw-bubble-holder"
       style="--w-brand: ${BRAND}; --w-on-brand: ${ON_BRAND};">
    <button class="woot-widget-bubble woot-elements--right">
      <svg viewBox="0 0 24 24"><path d="M4 4h16v12H7l-3 3z" fill="currentColor"/></svg>
    </button>
  </div>
</body></html>`);

const bubble = page.locator('.woot-widget-bubble');
await bubble.waitFor({ state: 'visible' });

const bgOf = () => bubble.evaluate(el => getComputedStyle(el).backgroundColor);

// 1) repouso
check('lançador em repouso usa a cor da inbox', await bgOf(), EXPECTED);

// 2) o estado que o defeito escondia
await bubble.hover();
// Âncora de conteúdo forte em vez de espera cega: só seguimos quando o Chromium
// confirma que o elemento casa `:hover`.
await page.waitForFunction(
  () => document.querySelector('.woot-widget-bubble:hover') !== null
);
check('lançador EM :hover continua na cor da inbox', await bgOf(), EXPECTED);

// 3) o ícone herda a decisão de contraste, em vez de branco cravado.
//    Duas asserções, porque a de cascade sozinha era frouxa: o `currentColor` do
//    HTML acima é escrito por este arquivo, então ela passaria mesmo se
//    `bubbleHelpers.js` seguisse cravando `#FFFFFF`. A segunda lê o arquivo real.
check(
  'ícone herda --w-on-brand por currentColor',
  await page
    .locator('.woot-widget-bubble path')
    .evaluate(el => getComputedStyle(el).fill),
  'rgb(0, 0, 0)'
);

const bubbleHelpers = readFileSync(
  new URL('../../bubbleHelpers.js', import.meta.url),
  'utf8'
);
check(
  'bubbleHelpers pinta o path com currentColor, não com branco cravado',
  String(
    /setAttributeNS\(null, 'fill', 'currentColor'\)/.test(bubbleHelpers) &&
      !/setAttributeNS\(null, 'fill', '#/.test(bubbleHelpers)
  ),
  'true'
);

// 4) o literal não pode existir no CSS, nem morto.
//    Comentários são removidos antes de medir: o `SDK_CSS` explica em prosa o
//    defeito que este bloco matou, e citar o hex numa explicação não pinta
//    pixel nenhum. O que não pode existir é DECLARAÇÃO com o literal.
const cssSemComentarios = SDK_CSS.replace(/\/\*[\s\S]*?\*\//g, '');
check(
  'nenhum #2dc46f em declaração do SDK_CSS',
  String(cssSemComentarios.toLowerCase().includes(GREEN)),
  'false'
);
// E a prova de que o strip não escondeu nada: nenhum hex de 6 dígitos sobrou em
// declaração, exceto os três tokens fixos que não dependem da inbox.
const hexEmDeclaracao = (
  cssSemComentarios.match(/#[0-9a-fA-F]{6}\b/g) || []
).sort();
check(
  'os únicos hex em declaração são os 3 tokens fixos',
  hexEmDeclaracao.join(','),
  '#F2F3F7,#ff4040,#ffffff'
);

// 5) a regra de hover tem de referenciar a var, não uma cor própria
check(
  'a regra :hover usa var(--w-brand)',
  String(
    /\.woot-widget-bubble:hover\s*\{[^}]*background:\s*var\(--w-brand\)/.test(
      SDK_CSS
    )
  ),
  'true'
);

await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
