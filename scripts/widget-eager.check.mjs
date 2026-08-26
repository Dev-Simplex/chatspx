#!/usr/bin/env node
/**
 * Verificador do bloco 2.18 — O QUE ESTÁ NO FIRST-PAINT DO WIDGET.
 *
 * O `widget-size.mjs` responde QUANTO pesa o grafo. Este responde O QUE há
 * dentro dele, que é a outra metade do aceite do 2.18: «`window.__SENTRY__` e
 * `window.amplitude` **undefined** dentro do iframe».
 *
 * POR QUE ELE NÃO USA `grep` NO BUNDLE. Procurar `"amplitude"` dentro do
 * arquivo gerado acha atributo de SVG (`<feTurbulence amplitude=…>`), string
 * de licença e comentário — já aconteceu nesta base. E o RÓTULO do chunk não
 * prova o conteúdo: antes deste bloco, `Validators-*.js` continha
 * `@sentry/core`, `vue-router` e `date-fns`, e nenhum validador. A única
 * fonte que não mente é `chunk.modules` do Rollup, que traz o fecho REAL de
 * módulos por chunk. É o que este verificador lê.
 *
 * Como produzir a entrada:
 *
 *   VITE_CHUNK_STATS=tmp/widget-eager-stats.json bin/vite build --force
 *   node scripts/widget-eager.check.mjs
 *
 * O `--force` NÃO é enfeite: o `bin/vite` do vite_ruby pula o build quando os
 * arquivos observados não mudaram («Skipping vite build»), e sem ele este
 * verificador leria o grafo do build anterior achando que leu o atual.
 *
 * Saída: 0 tudo certo, 1 proibido encontrado ou controle ausente, 2 não
 * consegui medir — porque "não consegui medir" nunca pode sair como verde.
 */
import fs from 'node:fs';
import path from 'node:path';

const flag = (nome, padrao) => {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? padrao : process.argv[i + 1];
};

const MANIFEST = path.resolve(flag('manifest', 'public/vite/.vite/manifest.json'));
const STATS = path.resolve(flag('stats', 'tmp/widget-eager-stats.json'));
const ENTRADA = 'entrypoints/widget.js';

/**
 * O que NÃO pode estar no fecho estático da entrada do widget.
 *
 * Cada linha é um aceite, não um gosto:
 *   · `@sentry/*` e `@amplitude/*` — aceite literal do 2.18.
 *   · `@formkit/*` — «FormKit só na rota do pré-chat». O pré-chat é uma rota
 *     `import()` e a maioria dos widgets nem tem pré-chat ligado.
 *   · os 39 idiomas que não são o `en` — «i18n sob demanda». `en` fica porque
 *     é o `fallbackLocale`: sem ele um chunk de idioma que não chega deixa o
 *     painel sem string nenhuma.
 */
const PROIBIDOS = [
  { rotulo: '@sentry/*', teste: id => /node_modules\/@sentry\//.test(id) },
  { rotulo: '@amplitude/*', teste: id => /node_modules\/@amplitude\//.test(id) },
  { rotulo: '@formkit/*', teste: id => /node_modules\/@formkit\//.test(id) },
  {
    rotulo: 'idioma do widget que não é o fallback `en`',
    teste: id =>
      /widget\/i18n\/locale\/[^/]+\.json$/.test(id) &&
      !id.endsWith('/locale/en.json'),
  },
];

/**
 * CONTROLES POSITIVOS — a defesa contra o verde no vácuo.
 *
 * Um verificador que só afirma AUSÊNCIA passa também quando não mediu nada:
 * manifest de outro build, entrada renomeada, stats de um bundle vazio. Estas
 * quatro coisas TÊM de estar no first-paint do widget; se alguma faltar, o
 * que quebrou foi a medição, não o código — e o verificador diz isso.
 */
const CONTROLES = [
  { rotulo: 'vue-i18n', teste: id => /node_modules\/vue-i18n\//.test(id) },
  { rotulo: 'vue-router', teste: id => /node_modules\/vue-router\//.test(id) },
  { rotulo: 'widget/App.vue', teste: id => id.endsWith('widget/App.vue') },
  {
    rotulo: 'widget/i18n/locale/en.json (o fallback)',
    teste: id => id.endsWith('widget/i18n/locale/en.json'),
  },
];

/**
 * Modo `--stats-only`: fecho calculado a partir do PRÓPRIO stats, sem
 * manifest. Existe para o A/B — comparar um stats guardado de ANTES da
 * mudança com o de DEPOIS, dias depois, sem precisar do build inteiro que
 * produziu cada um. O grafo é o mesmo: `chunk.imports` do Rollup são os
 * imports estáticos, os mesmos que o manifest publica por chave lógica.
 */
const statsOnly = process.argv.includes('--stats-only');

const morrer = msg => {
  process.stderr.write(`widget-eager: ${msg}\n`);
  process.exit(2);
};

if (!statsOnly && !fs.existsSync(MANIFEST)) {
  morrer(`manifest não encontrado em ${MANIFEST}`);
}
if (!fs.existsSync(STATS)) {
  morrer(
    `stats de chunk não encontrado em ${STATS}.\n` +
      `Rode: VITE_CHUNK_STATS=${path.relative(process.cwd(), STATS)} bin/vite build --force`
  );
}

const stats = JSON.parse(fs.readFileSync(STATS, 'utf8'));
const porArquivo = new Map(stats.chunks.map(c => [c.fileName, c]));
const manifest = statsOnly
  ? null
  : JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));

if (manifest && !manifest[ENTRADA]) {
  morrer(`entrada "${ENTRADA}" ausente do manifest`);
}

// Mesmo fecho que o `widget-size.mjs` cobra: só `imports` (estáticos), com
// dedup por chave do manifest. `dynamicImports` fica de fora de propósito —
// é exatamente o lugar para onde o FormKit e os idiomas foram empurrados.
const arquivos = new Set();
const faltando = new Set();

if (statsOnly) {
  const entrada = stats.chunks.find(c => c.isEntry && c.name === ENTRADA);
  if (!entrada) morrer('nenhum chunk de entrada ${ENTRADA} no stats');
  const visitarChunk = arquivo => {
    if (arquivos.has(arquivo)) return;
    const c = porArquivo.get(arquivo);
    if (!c) return faltando.add(arquivo);
    arquivos.add(arquivo);
    for (const imp of c.imports ?? []) visitarChunk(imp);
  };
  visitarChunk(entrada.fileName);
} else {
  const visitar = chave => {
    const no = manifest[chave];
    if (!no) return faltando.add(chave);
    if (arquivos.has(no.file)) return;
    arquivos.add(no.file);
    for (const imp of no.imports ?? []) visitar(imp);
  };
  visitar(ENTRADA);
}
if (faltando.size) morrer(`grafo incompleto: ${[...faltando].join(', ')}`);

const modulos = [];
const semStats = [];
for (const arquivo of arquivos) {
  const chunk = porArquivo.get(arquivo);
  if (!chunk) {
    semStats.push(arquivo);
    continue;
  }
  for (const m of chunk.modules) modulos.push({ ...m, chunk: arquivo });
}
if (semStats.length) {
  morrer(
    `${semStats.length} chunk(s) do fecho sem entrada no stats ` +
      `(${semStats.slice(0, 3).join(', ')}…). O stats é de OUTRO build — ` +
      `rode o build com --force e VITE_CHUNK_STATS antes deste verificador.`
  );
}

const curto = id =>
  id
    .replace(/^.*node_modules\/\.pnpm\/[^/]+\/node_modules\//, 'npm:')
    .replace(`${process.cwd()}/`, '');

const falhas = [];
console.log('');
console.log('VERIFICADOR DO FIRST-PAINT DO WIDGET — bloco 2.18');
console.log(
  `manifest .. ${statsOnly ? '(--stats-only: fecho tirado do próprio stats)' : path.relative(process.cwd(), MANIFEST)}`
);
console.log(`stats ..... ${path.relative(process.cwd(), STATS)}`);
console.log(`chunks .... ${arquivos.size}`);
console.log(`módulos ... ${modulos.length}`);
console.log('');

console.log('[1] CONTROLES POSITIVOS — se algum falhar, quem quebrou foi a medição');
for (const c of CONTROLES) {
  const achou = modulos.some(m => c.teste(m.id));
  console.log(`    ${achou ? 'OK   ' : 'FALHA'} ${c.rotulo}`);
  if (!achou) {
    falhas.push(
      `controle positivo ausente: ${c.rotulo} não está no fecho estático — ` +
        `o verificador não está medindo o grafo do widget.`
    );
  }
}

console.log('');
console.log('[2] PROIBIDOS NO FIRST-PAINT');
for (const p of PROIBIDOS) {
  const hits = modulos.filter(m => p.teste(m.id));
  if (hits.length === 0) {
    console.log(`    OK    ${p.rotulo} — nenhum módulo`);
    continue;
  }
  const bytes = hits.reduce((a, m) => a + m.renderedLength, 0);
  console.log(
    `    FALHA ${p.rotulo} — ${hits.length} módulo(s), ${bytes.toLocaleString('pt-BR')} B renderizados`
  );
  for (const h of hits.slice(0, 6)) {
    console.log(`          ${curto(h.id)}  [${h.chunk}]`);
  }
  if (hits.length > 6) console.log(`          … e mais ${hits.length - 6}`);
  falhas.push(
    `${p.rotulo}: ${hits.length} módulo(s) no fecho estático da entrada do widget ` +
      `(${bytes.toLocaleString('pt-BR')} B renderizados).`
  );
}

// O inventário por pacote sai sempre: quando falha, é onde se vê o que entrou;
// quando passa, é a foto que a próxima medição compara.
const porPacote = new Map();
for (const m of modulos) {
  const p = m.id.match(
    /node_modules\/\.pnpm\/[^/]+\/node_modules\/((?:@[^/]+\/)?[^/]+)/
  );
  const chave = p ? `npm:${p[1]}` : `src:${curto(m.id).split('/').slice(1, 4).join('/')}`;
  porPacote.set(chave, (porPacote.get(chave) || 0) + m.renderedLength);
}
console.log('');
console.log('[3] INVENTÁRIO DO FIRST-PAINT (B renderizados, 20 maiores)');
for (const [k, v] of [...porPacote].sort((a, b) => b[1] - a[1]).slice(0, 20)) {
  console.log(`    ${String(v.toLocaleString('pt-BR')).padStart(11)} B  ${k}`);
}

console.log('');
if (falhas.length === 0) {
  console.log('═══ VERDE — nada proibido no first-paint, e a medição se provou.');
  process.exit(0);
}
console.log(`═══ VERMELHO · ${falhas.length} problema(s)`);
for (const f of falhas) console.log(`    · ${f}`);
process.exit(1);
