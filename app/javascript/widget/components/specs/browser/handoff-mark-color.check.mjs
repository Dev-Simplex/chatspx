/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório. */
/**
 * Mecanismo de aceite do bloco 4.09 — a asserção "NUNCA roxo como marcador".
 *
 * A razão do plano: contra o azul, o roxo colapsa para ΔE 1,8 em deuteranopia —
 * quem tem essa deficiência vê os dois marcadores como o mesmo.
 *
 * MAS TROCAR DE COR SÓ MUDA A COLISÃO DE LUGAR. A resposta deste bloco é mais
 * forte: **cor não é o sinal**. Os dois marcadores — "entrou a equipe" e "voltou
 * o assistente" — são pintados IGUAIS de propósito, e quem os distingue é a
 * frase. Este verificador mede as duas coisas, em claro E em escuro.
 *
 * UMA GUARDA CONTRA O PRÓPRIO ERRO. A primeira versão deste arquivo não
 * carregava os valores dos tokens. `text-n-slate-11` compila para
 * `color: rgb(var(--slate-11) / …)`; com `--slate-11` indefinido a função
 * inteira é inválida e o Chromium devolve o preto herdado. O verificador dava
 * 4/4 — e teria dado 4/4 IGUAL se a classe fosse roxa. Agora os valores vêm dos
 * mixins de `_tokens_values.scss`, e há asserção exigindo que a cor NÃO seja
 * preto puro, porque preto puro aqui é sinal de fixture quebrado.
 *
 * Por que não é `.spec.js`: jsdom não resolve `@apply` nem calcula cor herdada.
 *
 *   node app/javascript/widget/components/specs/browser/handoff-mark-color.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';

const repoRoot = new URL('../../../../../../', import.meta.url).pathname;
const componente = readFileSync(
  new URL('../../AiHandoffMark.vue', import.meta.url),
  'utf8'
);
const tokensFonte = readFileSync(
  new URL('../../../assets/scss/_tokens_values.scss', import.meta.url),
  'utf8'
);

const results = [];
const check = (name, ok, detalhe) => {
  results.push({ name, ok });
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}\n        ${detalhe}`);
};

// ── 1. Classes E declarações cruas vêm do componente, não escritas aqui ─────
//
// Extrair só o `@apply` deixava um buraco que uma sabotagem revelou: um
// `color: #7c3aed` escrito direto na folha não passaria por lá, e a medição
// diria "não é roxo" sobre um marcador roxo. Agora o bloco `&__texto` inteiro é
// levado para a página — utilitárias e declarações.
const blocoTexto = componente.match(/&__texto \{([\s\S]*?)\n {2}\}/)?.[1];
if (!blocoTexto) {
  console.error('FALHA: não localizei o bloco &__texto em AiHandoffMark.vue');
  process.exit(1);
}
const applyTexto = (blocoTexto.match(/@apply ([^;]+);/)?.[1] || '')
  .replace(/\s+/g, ' ')
  .trim();
/** Declarações CSS cruas do bloco, sem o `@apply` e sem comentários. */
const declaracoesTexto = blocoTexto
  .replace(/@apply [^;]+;/g, '')
  .replace(/\/\/.*$/gm, '')
  .split('\n')
  .map(l => l.trim())
  .filter(l => /^[a-z-]+\s*:/.test(l))
  .join(' ');

if (!applyTexto && !declaracoesTexto) {
  console.error('FALHA: o bloco &__texto não declara estilo nenhum');
  process.exit(1);
}

const semComentarios = componente
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^\s*\/\/.*$/gm, '');
// `n-iris` fica FORA desta lista, e o motivo foi medido: neste fork a paleta
// "iris" foi rebrandeada para o verde da marca (`--iris-9: 45 196 111`, que é
// o #2dc46f). Proibi-la pelo nome barraria uma cor da casa e daria falso
// positivo — o nome herdado do Radix não descreve mais o que ela é. Quem decide
// se há roxo é a MEDIÇÃO abaixo, não o nome da classe.
check(
  'o componente não usa utilitária roxa declarada (purple/violet/indigo)',
  !/\b(?:text|bg|border)-(?:purple|violet|indigo)/.test(semComentarios),
  `classes do texto: ${applyTexto}`
);

// ── 2. Compila as utilities do widget — o CSS de verdade ────────────────────
const dir = mkdtempSync(join(tmpdir(), 'handoff-color-'));
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(inCss, '@tailwind utilities;\n');
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.widget.config.js',
    '-i',
    inCss,
    '-o',
    outCss,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(outCss, 'utf8');

// ── 3. Os VALORES dos tokens, lidos dos mixins do projeto ───────────────────
const mixin = nome => {
  const re = new RegExp('@mixin ' + nome + ' \\{([\\s\\S]*?)\\n\\}');
  const bloco = tokensFonte.match(re)?.[1];
  if (!bloco) {
    console.error(
      `FALHA: não localizei o mixin ${nome} em _tokens_values.scss`
    );
    process.exit(1);
  }
  return bloco;
};
const TOKENS = {
  claro: { vars: mixin('widget-palette-light'), fundo: '#ffffff' },
  escuro: { vars: mixin('widget-palette-dark'), fundo: '#111111' },
};

// ── 4. Mede as duas marcações no navegador, nos dois temas ──────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

const rgb = cor => (cor.match(/\d+/g) || []).map(Number).slice(0, 3);
/** Roxo grosseiro: azul e vermelho altos e verde nitidamente menor que os dois. */
const pareceRoxo = ([r, g, b]) => b > 90 && r > 90 && g < Math.min(r, b) - 30;

const medirTema = async (nome, { vars, fundo }) => {
  await page.setContent(`<!doctype html>
<html><head>
<style>${CSS}</style>
<style>:root { ${vars} }</style>
<style>.marca-teste { ${declaracoesTexto} }</style>
</head>
<body style="margin:0;background:${fundo}">
  <div id="para-humano" class="marca-teste ${applyTexto}">A partir daqui, quem responde e a equipe</div>
  <div id="para-ia" class="marca-teste ${applyTexto}">A partir daqui, quem responde e o assistente virtual</div>
</body></html>`);

  const corDe = sel =>
    page.locator(sel).evaluate(el => getComputedStyle(el).color);
  const corHumano = await corDe('#para-humano');
  const corIA = await corDe('#para-ia');

  check(
    `[${nome}] o token RESOLVEU — a medição está medindo de verdade`,
    corHumano !== 'rgb(0, 0, 0)',
    `cor computada = ${corHumano} (preto puro indicaria token não carregado)`
  );
  check(
    `[${nome}] a marcação "entrou a equipe" não é roxa`,
    !pareceRoxo(rgb(corHumano)),
    `cor computada = ${corHumano}`
  );
  check(
    `[${nome}] a marcação "voltou o assistente" não é roxa`,
    !pareceRoxo(rgb(corIA)),
    `cor computada = ${corIA}`
  );
  check(
    `[${nome}] as DUAS têm a mesma cor — cor não é o sinal, o texto é`,
    corHumano === corIA,
    `humano=${corHumano}  ia=${corIA}`
  );
};

await medirTema('claro', TOKENS.claro);
await medirTema('escuro', TOKENS.escuro);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
if (falhas.length) {
  console.error(`FALHOU: ${falhas.map(f => f.name).join(' · ')}`);
  process.exit(1);
}
console.log('TODAS as asserções medidas no Chromium passaram.');
