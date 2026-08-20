/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 3.14 — a parte de COR, que o jsdom não prova.
 *
 * O `PreChatFieldEditor.spec.js` assere que a mensagem de anti-lixo **não** tem
 * classe com `ruby` e que a de erro duro **tem**. Isso é ler a folha de estilo e
 * concluir: o jsdom vê a classe aplicada e dá verde sem resolver cascata,
 * `!important` ou custom property. Duas formas de o aceite estar errado
 * sobrevivem a esse teste:
 *
 *   1. a classe não existir no CSS compilado — o Tailwind descarta classe
 *      desconhecida em SILÊNCIO, e a mensagem de erro sairia na cor herdada;
 *   2. um catch-all do skin (`_wa-skin.scss` tem vários, com `!important`)
 *      prender as duas na MESMA cor, tornando "aviso" e "erro" indistinguíveis
 *      para quem olha a tela.
 *
 * A decisão de produto que isto protege é da §B.4.3: anti-lixo é **aviso**, não
 * barreira. Se as duas mensagens saem iguais, a tela promete um bloqueio que o
 * widget não aplica.
 *
 *   node app/javascript/dashboard/routes/dashboard/settings/inbox/widget/prechat/specs/browser/field-message-colors.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
// A raiz sai de subir ate o `package.json`, e nao de uma contagem de `../`:
// contar niveis quebra em silencio quando o arquivo muda de pasta.
const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('nao achei a raiz do repositorio');
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

// ── 1. As classes saem do `Input.vue` real ───────────────────────────────────
// É ele quem decide a cor por `messageType`; uma cópia aqui mediria uma fixture.
const input = readFileSync(
  join(repoRoot, 'app/javascript/dashboard/components-next/input/Input.vue'),
  'utf8'
);
const messageClass =
  /const messageClass = computed\(\(\) => \{([\s\S]*?)\n\}\);/.exec(input)[1];
const classeDe = caso => {
  const bloco = new RegExp(`case '${caso}':\\s*return\\s*'([^']*)'`).exec(
    messageClass
  );
  if (!bloco) throw new Error(`não achei a classe de messageType="${caso}"`);
  return bloco[1];
};
const CLASSE_ERRO = classeDe('error');
const CLASSE_AVISO = /default:\s*return\s*'([^']*)'/.exec(messageClass)[1];

// ── 2. O CSS de verdade ──────────────────────────────────────────────────────
const dir = mkdtempSync(join(tmpdir(), 'field-message-'));
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
const TAILWIND = readFileSync(outCss, 'utf8');
const SKIN = sass.compile(
  join(repoRoot, 'app/javascript/dashboard/assets/scss/_wa-skin.scss'),
  { style: 'expanded' }
).css;

// As custom properties do dashboard. Sem elas, `color: rgb(var(--ruby-9))` é
// declaração inválida e o texto herda preto — o harness mediria um vermelho que
// não é vermelho por culpa do próprio harness. (Foi o que aconteceu na primeira
// rodada: erro e aviso saíram os dois `rgb(0, 0, 0)` no tema claro.)
const NEXT_COLORS = sass.compile(
  join(repoRoot, 'app/javascript/dashboard/assets/scss/_next-colors.scss'),
  { style: 'expanded' }
).css;

const browser = await chromium.launch();
const page = await browser.newPage();

const medirNoTema = async temaEscuro => {
  await page.setContent(`<!doctype html>
<html${temaEscuro ? ' class="dark"' : ''}><head><style>
${NEXT_COLORS}
${TAILWIND}
${SKIN}
</style></head>
<body style="margin:0">
  <p id="erro" class="${CLASSE_ERRO}">Confira o CPF: os números não fecham.</p>
  <p id="aviso" class="${CLASSE_AVISO}">Esse nome parece incompleto. Confere?</p>
</body></html>`);
  await page.locator('#erro').waitFor({ state: 'visible' });
  const cor = selector =>
    page.$eval(selector, el => getComputedStyle(el).color);
  return { erro: await cor('#erro'), aviso: await cor('#aviso') };
};

// ── 3. Painel claro ──────────────────────────────────────────────────────────
const claro = await medirNoTema(false);
check(
  'no painel claro, o erro duro sai VERMELHO',
  claro.erro,
  'rgb(229, 70, 102)' // --ruby-9, `_next-colors.scss:61`
);
check(
  'no painel claro, o aviso de anti-lixo NÃO sai vermelho',
  String(claro.aviso !== claro.erro),
  'true'
);

// ── 4. Painel escuro — onde os catch-alls do skin agem ───────────────────────
const escuro = await medirNoTema(true);
check(
  'no painel escuro, o erro duro continua VERMELHO',
  escuro.erro,
  'rgb(229, 70, 102)' // --ruby-9 no bloco escuro, `_next-colors.scss:227`
);
check(
  'no painel escuro, aviso e erro continuam DISTINGUÍVEIS',
  String(escuro.aviso !== escuro.erro),
  'true'
);
console.log(
  `        (aviso claro=${claro.aviso}  aviso escuro=${escuro.aviso})`
);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
process.exit(falhas.length ? 1 : 0);
