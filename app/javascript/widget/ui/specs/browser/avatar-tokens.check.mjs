/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado dele. */
/**
 * Prova de que a tokenização do `WAvatar` (bloco 2.01) NÃO MOVE PIXEL.
 *
 * ── Por que precisa de navegador ─────────────────────────────────────────────
 *
 * O spec de unidade (`../WAvatar.spec.js`) compara STRINGS: que o token existe,
 * que o valor dele é o hexadecimal do original, que o componente aponta para o
 * índice certo. Isso cobre a tabela e o apontamento, e não cobre a CASCATA —
 * `var(--w-avatar-3-bg)` só vira uma cor depois que o navegador resolve o
 * `:root`/`.dark` onde o token foi declarado. Se o mixin escuro não chegasse ao
 * elemento, o teste de unidade continuaria verde e o avatar sairia claro no
 * tema escuro.
 *
 * Aqui os dois desenhos ficam LADO A LADO no mesmo documento: o antigo, com o
 * hexadecimal cravado no `style` (que é exatamente o que o componente emitia
 * antes), e o novo, com `var(--w-avatar-N-*)`. O que se compara é
 * `getComputedStyle` dos dois. Igual byte a byte = os 20 snapshots do widget
 * não se movem por causa deste bloco.
 *
 * ⚠️ NÃO USA O HARNESS DE PORTA FIXA. `chromium.launch()` direto, sem
 * `playwright.config.js`, sem `webServer`, sem 3038/3999/8899 — o harness é
 * recurso de slot único e está sob tranca do coordenador.
 *
 *   node app/javascript/widget/ui/specs/browser/avatar-tokens.check.mjs
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { chromium } from 'playwright';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '../../../../../..');

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

/** Os 26 hexadecimais que viviam DENTRO de `WAvatar.vue`, na ordem original. */
const ORIGINAL = {
  light: [
    ['#FBDCEF', '#C2298A'],
    ['#FFE0BB', '#99543A'],
    ['#E8E8E8', '#60646C'],
    ['#CCF3EA', '#008573'],
    ['#EBEBFE', '#4747C2'],
    ['#E1E9FF', '#3A5BC7'],
  ],
  dark: [
    ['#4B143D', '#FF8DCC'],
    ['#3F220D', '#FFA366'],
    ['#2A2A2A', '#ADB1B8'],
    ['#023B37', '#0BD8B6'],
    ['#27264D', '#A19EFF'],
    ['#1D2E62', '#9EB1FF'],
  ],
};
const OUTLINE_ORIGINAL = {
  light: 'rgb(0 0 0 / 0.03)',
  dark: 'rgb(255 255 255 / 0.04)',
};

// A folha de tokens de VERDADE, LIDA do arquivo do projeto — não uma cópia
// escrita aqui, que é o jeito mais fácil de um verificador passar medindo a si
// mesmo.
//
// O corpo dos dois mixins é CSS puro (só declarações de custom property), então
// ele é recortado em vez de compilado: `sass` não está içado para a raiz de
// `node_modules` neste projeto (pnpm), e depender do caminho interno do store
// quebraria o verificador na próxima instalação.
const TOKENS_SCSS = readFileSync(
  join(repoRoot, 'app/javascript/widget/assets/scss/_tokens_values.scss'),
  'utf8'
);
const corpoDoMixin = nome => {
  const corpo = TOKENS_SCSS.split(`@mixin ${nome} {`)[1]?.split('\n}')[0];
  if (!corpo) throw new Error(`mixin ${nome} não existe`);
  const declaracoes = [...corpo.matchAll(/(--w-avatar-[\w-]+):\s*([^;]+);/g)];
  // Guarda contra o recorte vazio: sem isto, um `@mixin` renomeado produziria
  // uma folha sem token nenhum e a comparação abaixo passaria comparando duas
  // cores herdadas.
  if (declaracoes.length < 7) {
    throw new Error(`${nome} rendeu só ${declaracoes.length} tokens`);
  }
  return declaracoes.map(m => `${m[1]}: ${m[2].trim()};`).join('\n  ');
};
const TOKENS = `:root {\n  ${corpoDoMixin('widget-avatar-light')}\n}
.dark {\n  ${corpoDoMixin('widget-avatar-dark')}\n}`;

// O `<style scoped>` do PRÓPRIO componente, extraído do arquivo. É de lá que sai
// o `outline-color: var(--w-avatar-outline)`.
const componente = readFileSync(
  join(repoRoot, 'app/javascript/widget/ui/WAvatar.vue'),
  'utf8'
);
// `//` é comentário de SCSS e NÃO é CSS: deixado no `<style>` do documento, o
// parser do navegador o lê como início de seletor e ENGOLE a regra seguinte —
// o `outline-color` sumiria e o verificador acusaria um defeito que não existe.
// No app quem tira isso é o compilador SCSS; aqui, esta linha.
const ESTILO_DO_COMPONENTE = /<style scoped lang="scss">([\s\S]*?)<\/style>/
  .exec(componente)[1]
  .replace(/^\s*\/\/.*$/gm, '');

const linha = (tom, tema) => {
  const [fundo, texto] = ORIGINAL[tema][tom - 1];
  return `
    <span id="antigo-${tema}-${tom}" class="face"
          style="background-color:${fundo};color:${texto};outline-color:${OUTLINE_ORIGINAL[tema]}">ML</span>
    <span id="novo-${tema}-${tom}" class="face w-avatar__face"
          style="background-color:var(--w-avatar-${tom}-bg);color:var(--w-avatar-${tom}-fg)">ML</span>`;
};

const tons = [1, 2, 3, 4, 5, 6];
const html = `<!doctype html>
<html lang="pt-BR"><head><title>t</title><style>
${TOKENS}
.face { display:inline-flex; width:32px; height:32px; outline:1px solid; outline-offset:-1px; }
${ESTILO_DO_COMPONENTE}
</style></head>
<body style="margin:0">
  <div id="claro">${tons.map(t => linha(t, 'light')).join('')}</div>
  <div id="escuro" class="dark">${tons.map(t => linha(t, 'dark')).join('')}</div>
</body></html>`;

const browser = await chromium.launch();
const contexto = await browser.newContext();
const page = await contexto.newPage();
await page.setContent(html);

const computed = (id, prop) =>
  page.$eval(
    `#${id}`,
    (el, property) => getComputedStyle(el).getPropertyValue(property),
    prop
  );

// As medições são SEQUENCIAIS de propósito: `page.$eval` fala com um único
// documento, e disparar 36 leituras em paralelo só troca ordem determinística
// por concorrência sem ganho nenhum de tempo de parede aqui.
const casos = ['light', 'dark'].flatMap(tema =>
  tons.flatMap(tom =>
    ['background-color', 'color', 'outline-color'].map(prop => ({
      tema,
      tom,
      prop,
    }))
  )
);

await casos.reduce(
  (anterior, { tema, tom, prop }) =>
    anterior.then(async () => {
      const antigo = await computed(`antigo-${tema}-${tom}`, prop);
      const novo = await computed(`novo-${tema}-${tom}`, prop);
      check(`${tema} · tom ${tom} · ${prop}`, novo, antigo);
    }),
  Promise.resolve()
);

// Guarda contra o falso verde deste arquivo: se o token não existisse, `var()`
// resolveria vazio e o navegador devolveria a cor herdada nos DOIS nós — e
// "vazio === vazio" passaria. Uma cor de verdade tem de sair do lado novo.
const amostra = await computed('novo-light-1', 'background-color');
check(
  'o lado novo pinta de verdade (não é var() vazio)',
  String(amostra.startsWith('rgb(') && amostra !== 'rgba(0, 0, 0, 0)'),
  'true'
);

await browser.close();

const falhas = results.filter(r => !r.ok).length;
console.log(
  `\n${results.length - falhas}/${results.length} asserções passaram em Chromium`
);
process.exit(falhas ? 1 : 0);
