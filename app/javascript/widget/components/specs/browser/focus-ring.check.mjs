/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e
   colada no relatório do bloco. Não é log esquecido em código de produção,
   que é o que a regra existe para pegar. */
/**
 * Mecanismo de aceite do bloco 1.06 — a terceira asserção: `outline-color` não
 * transparente, e anel de foco que de fato desenha.
 *
 * Por que não é um `.spec.js`: o que interessa aqui só existe depois do
 * Tailwind compilar e do navegador resolver a cascade. `outline-none` do
 * Tailwind gera `outline: 2px solid transparent` — um anel de 2px transparente
 * passa em qualquer teste de marcação e é invisível para quem navega por
 * teclado. Só `getComputedStyle` revela.
 *
 * POR QUE ESTE ARQUIVO FOI REESCRITO (bloco 1.06, 2ª passada)
 * ----------------------------------------------------------
 * Ele estava MORTO desde o 2.05. Lia `ChatInputWrap.vue` procurando
 * `class="items-center flex…"` e `'…shadow-focus…': isFocused`; o 2.05 esvaziou
 * aquele arquivo (virou casca de 36 linhas que só delega) e levou o composer
 * para `widget/ui/WComposer.vue`. Resultado: `node focus-ring.check.mjs` saía
 * "não localizei as classes do composer", exit 1, ZERO asserção executada.
 * Verificador que não acha o sujeito não mede nada — e este ficou meses assim
 * sem ninguém notar, porque exit 1 parecia "o bloco ainda não está pronto".
 *
 * Duas mudanças de fundo, além do caminho:
 *
 *   1. O sujeito agora são os DOIS lugares que o aceite cobre — o composer
 *      (`WComposer.vue`) e o checkbox do pré-chat (`PreChat/Form.vue`), que
 *      aplicava `outline-none` e por isso ganhava 2px de anel transparente.
 *
 *   2. Saiu a asserção `.shadow-focus existe no CSS compilado`. `shadow-focus`
 *      não é usada por NENHUM arquivo de código hoje (só por comentários e
 *      pelos planos), e ela era compilada com `tailwind.config.js` — a config
 *      do PAINEL. O widget builda com `tailwind.widget.config.js`, que sequer
 *      estende `boxShadow`. Era uma guarda no vácuo: media uma classe que
 *      ninguém aplica, a partir da config errada.
 *      No lugar dela entrou a guarda do MESMO perigo na forma de hoje: o anel
 *      é `outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color)`,
 *      e se o token não estiver declarado o navegador descarta a declaração
 *      INTEIRA — nenhum anel, nenhum aviso. Então os tokens são LIDOS de
 *      `_tokens_values.scss` (valor real, não inventado aqui) e a cor esperada
 *      é calculada a partir deles.
 *
 *   node app/javascript/widget/components/specs/browser/focus-ring.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('não achei a raiz do repositório');
    dir = acima;
  }
  return dir;
})();
const sass = require(
  join(repoRoot, 'node_modules/.pnpm/sass@1.79.3/node_modules/sass')
);

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// ── 0. Os sujeitos, por caminho — e a morte é ALTA se algum sumir ────────────
// O modo de falhar do arquivo antigo foi apontar para um sujeito que tinha
// mudado de lugar. Então cada leitura aqui explica o que esperava encontrar.
const ler = (caminho, oQueEsperava) => {
  const cheio = join(repoRoot, caminho);
  if (!existsSync(cheio)) {
    console.error(
      `FALHA: não existe ${caminho} — era onde vivia ${oQueEsperava}.\n` +
        'O sujeito mudou de lugar: conserte o CAMINHO aqui em vez de apagar a asserção.'
    );
    process.exit(1);
  }
  return readFileSync(cheio, 'utf8');
};

const COMPOSER = 'app/javascript/widget/ui/WComposer.vue';
const PRE_CHAT = 'app/javascript/widget/components/PreChat/Form.vue';
const TOKENS = 'app/javascript/widget/assets/scss/_tokens_values.scss';

const composer = ler(COMPOSER, 'o campo de composição do widget');
const preChat = ler(PRE_CHAT, 'o formulário de pré-chat');
const tokens = ler(TOKENS, 'os tokens de foco do widget');

// ── 1. Os tokens de foco existem e têm valor literal ────────────────────────
// Sem isto o resto é teatro: `outline: var(--x) solid var(--y)` com `--y`
// indefinido é declaração INVÁLIDA, descartada inteira pelo navegador.
const tokenDe = nome =>
  new RegExp(`^\\s*--${nome}:\\s*([^;]+);`, 'm').exec(tokens)?.[1]?.trim();

const corToken = tokenDe('w-focus-ring-color');
const larguraToken = tokenDe('w-focus-ring-width');
const offsetToken = tokenDe('w-focus-ring-offset');

check(
  `os três tokens de foco estão declarados em ${TOKENS.split('/').pop()}`,
  JSON.stringify([corToken, larguraToken, offsetToken].map(Boolean)),
  '[true,true,true]'
);
if (!corToken || !larguraToken || !offsetToken) {
  console.error('FALHA: sem os tokens não há anel para medir.');
  process.exit(1);
}

// A cor esperada vem do TOKEN, não de um literal cravado aqui.
const hexParaRgb = hex => {
  const m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
  if (!m) return null;
  const [r, g, b] = m.slice(1).map(h => parseInt(h, 16));
  return `rgb(${r}, ${g}, ${b})`;
};
const corEsperada = hexParaRgb(corToken);
check(
  'o token de cor é um literal que dá para medir (não um `var()` encadeado)',
  String(corEsperada !== null),
  'true'
);

// ── 2. Nenhum dos dois sujeitos volta a aplicar `outline-none` ──────────────
// Asserção textual sobre os arquivos REAIS. Comentários saem antes: os dois
// explicam em prosa por que `outline-none` foi tirado, e citar o nome do
// utilitário numa explicação não pinta anel nenhum.
const semComentarios = fonte =>
  fonte
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '');

check(
  'WComposer não aplica outline-none em classe nenhuma',
  String(/\boutline-none\b/.test(semComentarios(composer))),
  'false'
);
check(
  'PreChat/Form não aplica outline-none em classe nenhuma',
  String(/\boutline-none\b/.test(semComentarios(preChat))),
  'false'
);

// ── 3. Compila o CSS de verdade: sass resolve o aninhamento, Tailwind o @apply
// A mesma ordem do build do Vite, e com `tailwind.widget.config.js` — a config
// com que o widget realmente builda.
const estiloDe = (sfc, nome) => {
  const m = /<style[^>]*lang="scss"[^>]*>([\s\S]*?)<\/style>/.exec(sfc);
  if (!m) {
    console.error(`FALHA: não achei o bloco <style lang="scss"> de ${nome}.`);
    process.exit(1);
  }
  return m[1];
};

const cssComApply = sass.compileString(
  `${estiloDe(composer, COMPOSER)}\n${estiloDe(preChat, PRE_CHAT)}`,
  { style: 'expanded' }
).css;

const dir = mkdtempSync(join(tmpdir(), 'focus-ring-'));
const entrada = join(dir, 'in.css');
const saida = join(dir, 'out.css');
writeFileSync(entrada, `@tailwind utilities;\n${cssComApply}`);
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.widget.config.js',
    '-i',
    entrada,
    '-o',
    saida,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(saida, 'utf8');

// ── 4. Mede no navegador ────────────────────────────────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

await page.setContent(`<!doctype html>
<html><head><style>
  :root {
    --w-focus-ring-color: ${corToken};
    --w-focus-ring-width: ${larguraToken};
    --w-focus-ring-offset: ${offsetToken};
  }
  * { box-sizing: border-box; }
  body { margin: 0; }
  ${CSS}
</style></head>
<body>
  <!-- Trampolim: o Tab só conta como navegação de teclado se PARTIR de algum
       lugar. Focar este e teclar Tab leva o foco ao checkbox pelo mesmo
       caminho de quem navega sem mouse. -->
  <button id="trampolim">.</button>
  <div class="formkit-outer">
    <div class="formkit-inner">
      <input id="aceite" type="checkbox" />
    </div>
  </div>
  <div class="w-composer">
    <textarea id="campo" class="w-composer__campo" rows="1"></textarea>
  </div>
</body></html>`);
await page.locator('#campo').waitFor({ state: 'visible' });

const anelDe = id =>
  page.$eval(id, el => {
    const s = getComputedStyle(el);
    return {
      largura: s.outlineWidth,
      cor: s.outlineColor,
      estilo: s.outlineStyle,
    };
  });

// O composer: `focus()` basta — campo de texto sempre casa `:focus-visible`.
await page.focus('#campo');
const anelCampo = await anelDe('#campo');
check(
  'composer focado: anel com largura > 0',
  String(parseFloat(anelCampo.largura) > 0),
  'true'
);
check(
  'composer focado: estilo do anel não é `none`',
  anelCampo.estilo,
  'solid'
);
check(
  'composer focado: a cor do anel é a do token, NÃO transparente',
  anelCampo.cor,
  corEsperada
);

// O checkbox do pré-chat: aqui `focus()` NÃO serve. Chromium só casa
// `:focus-visible` num checkbox quando o foco veio do TECLADO — foco
// programático deixaria a regra sem aplicar e este teste mediria um anel
// ausente por motivo errado, acusando um defeito que não existe. Por isso Tab:
// é o caminho real de quem navega por teclado, que é justamente quem depende
// do anel.
await page.focus('#trampolim');
await page.keyboard.press('Tab');
// Esta asserção é a que impede as duas de baixo de medirem o anel PADRÃO do
// Chromium num checkbox que nunca recebeu foco — foi exatamente o que
// aconteceu na primeira versão deste trecho: `largura > 0` passou e a cor veio
// `rgb(0, 0, 0)`, que é o UA, não o nosso token.
check(
  'o Tab realmente pousou no checkbox do pré-chat',
  await page.evaluate(() => document.activeElement?.id),
  'aceite'
);

const anelCheckbox = await anelDe('#aceite');
check(
  'checkbox do pré-chat focado: anel com largura > 0',
  String(parseFloat(anelCheckbox.largura) > 0),
  'true'
);
check(
  'checkbox do pré-chat focado: estilo do anel não é `none`',
  anelCheckbox.estilo,
  'solid'
);
check(
  'checkbox do pré-chat focado: a cor do anel é a do token, NÃO transparente',
  anelCheckbox.cor,
  corEsperada
);

// A asserção do aceite, varrendo os dois sujeitos de uma vez: nenhum elemento
// pode ter anel de largura visível E cor transparente. `outline-0` zera a
// largura; `outline-none` deixava 2px transparentes, que é o defeito.
const anelFantasma = await page.evaluate(() =>
  [...document.querySelectorAll('*')]
    .map(el => {
      const s = getComputedStyle(el);
      return {
        alvo: el.id || el.className || el.tagName,
        estilo: s.outlineStyle,
        largura: s.outlineWidth,
        cor: s.outlineColor,
      };
    })
    .filter(
      o =>
        o.estilo !== 'none' &&
        parseFloat(o.largura) > 0 &&
        (o.cor === 'rgba(0, 0, 0, 0)' || o.cor === 'transparent')
    )
);
check(
  'nenhum elemento com anel de largura > 0 e cor transparente',
  JSON.stringify(anelFantasma),
  '[]'
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções ok`
);
process.exit(falhas.length ? 1 : 0);
