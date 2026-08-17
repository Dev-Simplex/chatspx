#!/usr/bin/env node
/**
 * Gate de peso do widget — mede o GRAFO, não o chunk de entrada.
 *
 * Bloco 0.5 do PLANO-MESTRE do redesenho (§2.2, §12.3, arbitragem A13).
 *
 * Por que este arquivo existe (os três falsos verdes que ele fecha):
 *
 *   1. O `size-limit` do `package.json` casava `public/vite/assets/widget-*.js`.
 *      Glob sobre nome com hash: o que ele mede depende do build, e o que ele
 *      NÃO mede é o resto do grafo. Aqui a fonte é o manifest do Vite, pela
 *      chave lógica da entrada (`entrypoints/widget.js`), que não tem hash.
 *
 *   2. O que o `size-limit` media era o chunk de entrada, não o fecho
 *      transitivo dos imports estáticos — que é o que o visitante realmente
 *      baixa antes do primeiro paint. São ~28 kB gzip contra ~420 kB. A
 *      travessia recursiva de `imports` (com dedup: asset compartilhado conta
 *      UMA vez) é o bloco inteiro. O aceite pede que esse número seja
 *      REPORTADO; a régua sobre ele é de regressão (ver LIMITS abaixo).
 *
 *   3. O `sdk.js` não tinha teto em gzip. É o único arquivo que 100% dos
 *      visitantes de todos os sites de todos os clientes baixa, e oito blocos
 *      do plano acrescentam código eager a ele (A13).
 *
 * ATENÇÃO À UNIDADE DO GZIP. A linha de base da §12 (9.595 B) foi medida com
 * `gzip -c public/packs/js/sdk.js | wc -c` — e o gzip(1) grava o nome do
 * arquivo original no header quando recebe um caminho, o que soma 7 bytes
 * ("sdk.js" + NUL). Para o `sdk.js`, cujo caminho é fixo, este gate reproduz
 * esse mesmo comando: assim o delta nasce em 0 e não em -7. Para os assets do
 * grafo, cujos nomes carregam hash de build, o gate mede com `gzip -nc <` —
 * sem nome e sem timestamp, determinístico — porque nome de arquivo não pode
 * entrar num orçamento de bytes.
 *
 * Uso:
 *   node scripts/widget-size.mjs
 *   node scripts/widget-size.mjs --json
 *   node scripts/widget-size.mjs --manifest <path> --sdk <path>   # fixtures
 *
 * Saída: 0 se todos os tetos passam, 1 se qualquer um falha.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// ── Orçamentos declarados (PLANO-MESTRE §2.2 bloco 0.5, A13, §12) ───────────
// KB decimal (1 KB = 1000 B), a mesma unidade do `size-limit` que já rodava.
const LIMITS = {
  // TETO DE REGRESSÃO, NÃO ALVO — e a distinção importa.
  //
  // O aceite do bloco 0.5 pede que o grafo seja REPORTADO ("reporta ~575 KiB,
  // não 76,53 kB"); as duas condições de FALHA que ele nomeia são outras — o
  // Leaflet e o `sdk.js`. Aplicar ao grafo o antigo teto de 300 kB seria
  // comparar coisas diferentes: aquele número foi escrito para o chunk de
  // entrada, e o grafo nasceria violado, vermelho para sempre e sem detectar
  // nada. Gate que é ruído vira gate ignorado.
  //
  // Então o valor abaixo é o JS eager gzip MEDIDO no build limpo desta árvore
  // — nem redondo, nem arredondado para cima, de propósito: o gate nasce verde
  // e fica vermelho no instante em que o grafo crescer um byte.
  //
  // O ALVO real é de outro bloco: 1.08 traz o CSS do widget para <= 80 KB
  // crus (hoje 1.692.256 B, com 7 `@font-face` que ninguém baixa) e 2.18 traz
  // o JS eager para <= 150 KB gzip. Quando cada um desses fechar, é ele quem
  // baixa este número — não o contrário.
  // Medido em 17/08/2026 no `redesenho-build` (HEAD 301bbdfdf9, o 0.3), com
  // `bin/vite build` limpo — e o mesmo número saiu do worktree do merge
  // (8684f07304), o que confirma que as duas árvores são iguais para o widget.
  widgetGraphGzip: 422_599,
  sdkGzip: 15_000, // A13 — protege o visitante (byte que atravessa a rede)
  sdkRaw: 40_000, // A13 — protege o parse (já era o teto do size-limit)
};

// §12, re-medido no worktree do merge em 17/08/2026. NÃO alterar sem decisão
// do coordenador: o delta em bytes de todo PR que toca `sdk/` sai daqui.
const SDK_BASELINE = { raw: 29_014, gzip: 9_595 };

const WIDGET_ENTRY = 'entrypoints/widget.js';
// Trava nominal do Leaflet: o dashboard carrega o mapa por `import()` dinâmico
// (`LocationPickerModal.vue:88-95`). Se algum dia voltar a ser import estático,
// o chunk reaparece no fecho estático de um entrypoint e o gate nomeia.
const LEAFLET_RE = /(^|\/)leaflet[-.].*\.js$/i;

// ── Args ────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};
const asJson = argv.includes('--json');
const manifestPath = path.resolve(
  flag('manifest', 'public/vite/.vite/manifest.json')
);
// O manifest mora em <assetsRoot>/.vite/manifest.json.
const assetsRoot = path.resolve(
  flag('assets-root', path.dirname(path.dirname(manifestPath)))
);
const sdkPath = path.resolve(flag('sdk', 'public/packs/js/sdk.js'));

// ── Medição ─────────────────────────────────────────────────────────────────
const rawSize = file => fs.statSync(file).size;

/** gzip determinístico: sem nome de arquivo, sem timestamp no header. */
const gzipSize = file =>
  execFileSync('gzip', ['-nc'], {
    input: fs.readFileSync(file),
    maxBuffer: 1 << 28,
  }).length;

/** gzip com FNAME no header — o comando exato que produziu a linha de base §12. */
const gzipSizeCanonical = file =>
  execFileSync('gzip', ['-c', file], { maxBuffer: 1 << 28 }).length;

// ── Travessia do grafo ──────────────────────────────────────────────────────
/**
 * Fecho transitivo dos imports ESTÁTICOS de uma entrada do manifest.
 * `dynamicImports` fica de fora de propósito: é código que o visitante só baixa
 * se navegar até ele, e o teto de first-paint não deve cobrá-lo.
 * Dedup por chave do manifest: um asset compartilhado conta uma vez.
 */
function staticClosure(manifest, entryKey) {
  const js = new Set();
  const css = new Set();
  const assets = new Set();
  const missing = new Set();

  const visit = key => {
    const node = manifest[key];
    if (!node) {
      missing.add(key);
      return;
    }
    if (js.has(node.file)) return;
    js.add(node.file);
    for (const c of node.css ?? []) css.add(c);
    for (const a of node.assets ?? []) assets.add(a);
    for (const imp of node.imports ?? []) visit(imp);
  };
  visit(entryKey);

  return { js, css, assets, missing };
}

function weigh(files) {
  let raw = 0;
  let gzip = 0;
  const rows = [];
  for (const rel of files) {
    const abs = path.join(assetsRoot, rel);
    const r = rawSize(abs);
    const g = gzipSize(abs);
    raw += r;
    gzip += g;
    rows.push({ file: rel, raw: r, gzip: g });
  }
  rows.sort((a, b) => b.gzip - a.gzip);
  return { raw, gzip, rows };
}

// ── Formatação ──────────────────────────────────────────────────────────────
const n = v => v.toLocaleString('pt-BR');
const dec2 = v =>
  v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const kib = v => `${dec2(v / 1024)} KiB`;
const signed = v => `${v >= 0 ? '+' : '−'}${n(Math.abs(v))} B`;
const pct = (delta, base) =>
  base === 0 ? 'n/d' : `${delta >= 0 ? '+' : '−'}${dec2(Math.abs((delta / base) * 100))}%`;

const out = [];
const say = line => out.push(line);

// ── Execução ────────────────────────────────────────────────────────────────
if (!fs.existsSync(manifestPath)) {
  process.stderr.write(
    `widget-size: manifest não encontrado em ${manifestPath}\n` +
      `Rode \`bin/vite build\` (ou \`bundle exec rake assets:precompile\`) antes do gate.\n`
  );
  process.exit(2);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const failures = [];
const report = { manifest: manifestPath, checks: {} };

say('');
say('GATE DE PESO DO WIDGET — mede o GRAFO (fecho transitivo do manifest),');
say('não o chunk de entrada. PLANO-MESTRE bloco 0.5 · A13 · §12.3');
say('');
say(`manifest .............. ${path.relative(process.cwd(), manifestPath)}`);

// ── [1] grafo do widget ─────────────────────────────────────────────────────
const entry = manifest[WIDGET_ENTRY];
if (!entry) {
  process.stderr.write(
    `widget-size: entrada "${WIDGET_ENTRY}" ausente do manifest. ` +
      `O gate ficaria cego — abortando em vez de reportar verde.\n`
  );
  process.exit(2);
}

const closure = staticClosure(manifest, WIDGET_ENTRY);
if (closure.missing.size) {
  process.stderr.write(
    `widget-size: imports sem entrada no manifest (grafo incompleto): ` +
      `${[...closure.missing].join(', ')}\n`
  );
  process.exit(2);
}

const jsWeight = weigh(closure.js);
const cssWeight = weigh(closure.css);
const entryOnly = weigh([entry.file]);
const totalRaw = jsWeight.raw + cssWeight.raw;
const totalGzip = jsWeight.gzip + cssWeight.gzip;
const graphDelta = jsWeight.gzip - LIMITS.widgetGraphGzip;
const graphOk = graphDelta <= 0;

say(`entrada ............... ${WIDGET_ENTRY} → ${entry.file}`);
say('');
say('[1] GRAFO DO WIDGET — first-paint (entrada + imports estáticos, dedup)');
say(`    módulos JS ........ ${closure.js.size}`);
say(
  `    JS eager .......... ${n(jsWeight.raw).padStart(11)} B crus  ${n(jsWeight.gzip).padStart(9)} B gzip`
);
say(
  `    CSS (${closure.css.size} arq.) ...... ${n(cssWeight.raw).padStart(11)} B crus  ${n(cssWeight.gzip).padStart(9)} B gzip`
);
say(
  `    GRAFO TOTAL ....... ${n(totalRaw).padStart(11)} B crus  ${n(totalGzip).padStart(9)} B gzip  (${kib(totalGzip)})`
);
say(
  `    chunk de entrada .. ${n(entryOnly.raw).padStart(11)} B crus  ${n(entryOnly.gzip).padStart(9)} B gzip  ← o que o glob media`
);
say(
  `    fontes .woff2 ..... ${n(weigh(closure.assets).raw).padStart(11)} B crus  (${closure.assets.size} arq., fora da régua — ver bloco 1.08)`
);
say(`    teto de REGRESSÃO .. ${n(LIMITS.widgetGraphGzip)} B gzip (JS eager; não é o alvo — ver 1.08 e 2.18)`);
if (graphOk) {
  say(`    OK — ${graphDelta === 0 ? 'na régua, sem regressão' : `${n(-graphDelta)} B abaixo da régua`}`);
} else {
  say(
    `    FALHA — o grafo CRESCEU ${signed(graphDelta)} (${pct(graphDelta, LIMITS.widgetGraphGzip)}) ` +
      `sobre a régua de ${n(LIMITS.widgetGraphGzip)} B`
  );
  failures.push(
    `grafo do widget cresceu: ${n(jsWeight.gzip)} B gzip > régua ${n(LIMITS.widgetGraphGzip)} B (${signed(graphDelta)})`
  );
}
say('    módulos do grafo, por peso gzip:');
for (const r of jsWeight.rows) {
  say(`      ${n(r.gzip).padStart(9)} B gzip  ${n(r.raw).padStart(9)} B crus  ${r.file}`);
}
for (const r of cssWeight.rows) {
  say(`      ${n(r.gzip).padStart(9)} B gzip  ${n(r.raw).padStart(9)} B crus  ${r.file}  [css]`);
}

report.checks.widgetGraph = {
  ok: graphOk,
  modules: closure.js.size,
  jsRaw: jsWeight.raw,
  jsGzip: jsWeight.gzip,
  cssRaw: cssWeight.raw,
  cssGzip: cssWeight.gzip,
  totalRaw,
  totalGzip,
  entryRaw: entryOnly.raw,
  entryGzip: entryOnly.gzip,
  limit: LIMITS.widgetGraphGzip,
  delta: graphDelta,
};

// ── [2] trava nominal do Leaflet ────────────────────────────────────────────
const entryKeys = Object.keys(manifest).filter(k => manifest[k].isEntry);
const leafletHits = [];
for (const key of entryKeys) {
  const { js } = staticClosure(manifest, key);
  for (const file of js) {
    if (LEAFLET_RE.test(file)) leafletHits.push({ entry: key, file });
  }
}

say('');
say('[2] TRAVA NOMINAL DO LEAFLET — `leaflet-*.js` no fecho ESTÁTICO');
say(`    entradas varridas . ${entryKeys.length}`);
if (leafletHits.length === 0) {
  say('    OK — nenhum `leaflet-*.js` em import estático (segue por `import()`)');
} else {
  for (const hit of leafletHits) {
    say(`    FALHA — ${hit.file} é import ESTÁTICO de ${hit.entry}`);
    failures.push(`leaflet estático: ${hit.file} no fecho de ${hit.entry}`);
  }
  say('    O mapa tem de continuar em `import()` dinâmico');
  say('    (dashboard/components-next/location/LocationPickerModal.vue:88-95).');
}
report.checks.leaflet = { ok: leafletHits.length === 0, hits: leafletHits };

// ── [3] sdk.js ──────────────────────────────────────────────────────────────
say('');
say('[3] sdk.js — a vantagem nº 1 (100% dos visitantes de todos os sites)');
if (!fs.existsSync(sdkPath)) {
  say(`    FALHA — ${sdkPath} não existe. Rode \`pnpm build:sdk\`.`);
  failures.push(`sdk.js ausente em ${sdkPath}`);
  report.checks.sdk = { ok: false, missing: true };
} else {
  const sdkRaw = rawSize(sdkPath);
  const sdkGzip = gzipSizeCanonical(sdkPath);
  const sdkGzipDet = gzipSize(sdkPath);
  const dRaw = sdkRaw - SDK_BASELINE.raw;
  const dGzip = sdkGzip - SDK_BASELINE.gzip;
  const rawOk = sdkRaw <= LIMITS.sdkRaw;
  const gzipOk = sdkGzip <= LIMITS.sdkGzip;

  say(`    arquivo ........... ${path.relative(process.cwd(), sdkPath)}`);
  say(
    `    cru ............... ${n(sdkRaw).padStart(9)} B   teto ${n(LIMITS.sdkRaw)} B   ` +
      (rawOk ? `OK (folga ${n(LIMITS.sdkRaw - sdkRaw)} B)` : `FALHA (${signed(sdkRaw - LIMITS.sdkRaw)})`)
  );
  say(
    `    gzip .............. ${n(sdkGzip).padStart(9)} B   teto ${n(LIMITS.sdkGzip)} B   ` +
      (gzipOk ? `OK (folga ${n(LIMITS.sdkGzip - sdkGzip)} B)` : `FALHA (${signed(sdkGzip - LIMITS.sdkGzip)})`)
  );
  say(`    linha de base §12 . ${n(SDK_BASELINE.raw)} B crus / ${n(SDK_BASELINE.gzip)} B gzip`);
  say(
    `    DELTA ............. cru ${signed(dRaw)} (${pct(dRaw, SDK_BASELINE.raw)})   ` +
      `gzip ${signed(dGzip)} (${pct(dGzip, SDK_BASELINE.gzip)})`
  );
  say(
    `    (gzip medido como \`gzip -c <arquivo> | wc -c\`, o comando da §12; sem o` +
      ` FNAME do header são ${n(sdkGzipDet)} B)`
  );

  if (!rawOk) {
    failures.push(
      `sdk.js cru: ${n(sdkRaw)} B > teto ${n(LIMITS.sdkRaw)} B (delta contra a base: ${signed(dRaw)})`
    );
  }
  if (!gzipOk) {
    failures.push(
      `sdk.js gzip: ${n(sdkGzip)} B > teto ${n(LIMITS.sdkGzip)} B (delta contra a base: ${signed(dGzip)})`
    );
  }
  report.checks.sdk = {
    ok: rawOk && gzipOk,
    raw: sdkRaw,
    gzip: sdkGzip,
    gzipDeterministic: sdkGzipDet,
    baseline: SDK_BASELINE,
    deltaRaw: dRaw,
    deltaGzip: dGzip,
    limitRaw: LIMITS.sdkRaw,
    limitGzip: LIMITS.sdkGzip,
  };
}

// ── Veredito ────────────────────────────────────────────────────────────────
say('');
if (failures.length === 0) {
  say('VERDE — os três tetos passam.');
} else {
  say(`VERMELHO — ${failures.length} teto(s) estourado(s):`);
  for (const f of failures) say(`  · ${f}`);
}
say('');

report.ok = failures.length === 0;
report.failures = failures;

process.stdout.write(asJson ? `${JSON.stringify(report, null, 2)}\n` : `${out.join('\n')}\n`);
process.exit(failures.length === 0 ? 0 : 1);
