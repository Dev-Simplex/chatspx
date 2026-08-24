#!/usr/bin/env node
/**
 * Gate de peso do widget — mede o GRAFO, não o chunk de entrada.
 *
 * Bloco 0.5 do PLANO-MESTRE do redesenho (§2.2, §12.3, arbitragem A13, R17).
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
 *      baixa antes do primeiro paint. São ~28 kB gzip contra ~423 kB. A
 *      travessia recursiva de `imports` (com dedup: asset compartilhado conta
 *      UMA vez) é o bloco inteiro.
 *
 *   3. O `sdk.js` não tinha teto em gzip. É o único arquivo que 100% dos
 *      visitantes de todos os sites de todos os clientes baixa, e oito blocos
 *      do plano acrescentam código eager a ele (A13).
 *
 * ESTE GATE NASCE VERMELHO, E ISSO É O PROJETO — não um defeito dele.
 * O teto de 300 kB é o mesmo que já estava declarado no `size-limit`; o que
 * mudou é que agora ele é cobrado do grafo, e o grafo o estoura em ~41%. A
 * §12.3 do PLANO-MESTRE decidiu, antes desta execução, que o teto NÃO se
 * afrouxa para acomodar o número: quem o derruba é o bloco 1.08.
 *
 * O risco R17 do plano é justamente "gate ligado com teto inalcançável → o time
 * desliga o gate". Um CI permanentemente vermelho treina gente a ignorar CI.
 * A defesa aqui NÃO é afrouxar o teto — é a mensagem: toda falha se classifica
 * em DÍVIDA CONHECIDA (já estava aqui, rastreada, com dono nomeado) ou
 * REGRESSÃO NOVA (entrou agora, é de quem está vendo o vermelho). E a dívida
 * carrega a LINHA DE BASE DO DIA em que o gate nasceu, para que piorar de 41%
 * para 60% seja visível — sem ela, um gate sempre vermelho fica cego.
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
 *   node scripts/widget-size.mjs --manifest <path> --sdk <path>   # ver AVISO
 *
 * Saída: 0 se todos os tetos passam, 1 se qualquer um falha, 2 se o gate não
 * conseguiu medir (sem manifest, entrada ausente, grafo incompleto) — porque
 * "não consegui medir" nunca pode sair como verde.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// ── Orçamentos declarados (PLANO-MESTRE §2.2 bloco 0.5, A13, §12.3) ─────────
// KB decimal (1 KB = 1000 B), a mesma unidade do `size-limit` que já rodava.
const LIMITS = {
  // TETO. Não é alvo, não é régua de regressão: é teto, e está estourado.
  //
  // 300 kB gzip é o número que o `size-limit` já declarava para
  // `public/vite/assets/widget-*.js` antes deste bloco. O bloco não inventou
  // um teto novo nem herdou um mais folgado — ele passou a cobrar o mesmo
  // número do artefato certo (o fecho estático de first-paint) em vez do
  // chunk de entrada, e aí o teto aparece violado em ~41%.
  //
  // NÃO ALTERE ESTE VALOR PARA "FAZER PASSAR". A §12.3 registra a decisão:
  // "O teto de 300 kB não se afrouxa para acomodar o número; quem o baixa é o
  // bloco 1.08". Este é o único teto do plano que protege 100% dos visitantes
  // de todos os sites de todos os clientes. Baixá-lo é negociar aceite
  // numérico, o que a §4 proíbe.
  widgetGraphGzip: 300_000,
  sdkGzip: 15_000, // A13 — protege o visitante (byte que atravessa a rede)
  sdkRaw: 40_000, // A13 — protege o parse (já era o teto do size-limit)
};

// A DÍVIDA, MEDIDA NO DIA EM QUE O GATE NASCEU.
//
// Sem esta linha, o vermelho permanente vira cego: ninguém percebe quando o
// grafo passar de 41% para 60% acima do teto, porque a mensagem diria "acima
// do teto" nos dois casos. Com ela, o gate separa a dívida herdada da piora
// nova, e é a piora nova que cobra de quem está vendo o vermelho.
//
// ATUALIZAR SÓ PARA BAIXO, e só quando um bloco tiver de fato derrubado o
// número (1.08 → CSS; 2.18 → JS eager ≤ 150 KB gzip). Subir este valor para
// acomodar código novo é o mesmo afrouxamento que o teto proíbe.
const GRAPH_BASELINE = {
  // BAIXADA PELO BLOCO 2.18, e só para baixo — é o que a própria mensagem de
  // sucesso deste gate manda fazer quando o grafo entra no teto: sem isso a
  // régua de regressão ficaria frouxa em 132.968 B e qualquer PR poderia
  // devolver todo o emagrecimento sem o gate dizer nada.
  //
  // O que derrubou os 132.968 B (medido com `chunk.modules` do Rollup, não com
  // grep no bundle):
  //   · i18n sob demanda — 39 dos 40 idiomas viraram `import()`  ......  ~193 kB renderizados
  //   · FormKit só na rota do pré-chat  ................................  ~203 kB renderizados
  //   · `vue` na build runtime-only (o compilador de template só no portal)   ~169 kB renderizados
  //
  // O teto de 300.000 CONTINUA INTOCADO. O aceite do 2.18 pede JS eager
  // ≤ 150 KB gzip e ele ainda NÃO foi alcançado: faltam Sentry, date-fns,
  // markdown-it, axios e urlpattern saírem do first-paint, e os cinco moram em
  // arquivo de outra trilha.
  gzip: 289_631,
  date: '24/08/2026',
  where: 'worktree do bloco 2.18, `bin/vite build --force` limpo',
  // Tolerância do eixo de REGRESSÃO — não do teto, que não tem nenhuma.
  //
  // O gzip do grafo não é bit-a-bit reprodutível entre dois builds do MESMO
  // código: cada chunk carrega no corpo os nomes hasheados dos seus imports e
  // o próprio `sourceMappingURL`, e o hash muda a compressão. Medido em
  // 17/08/2026 sobre os 15 arquivos do grafo, re-hasheando todos os nomes 50
  // vezes: amplitude de 57 B, desvio de −10 a +47 B contra o build real. Dois
  // builds consecutivos reais diferiram em 3 B.
  //
  // 256 B é ~4,5x a amplitude medida e 0,06% do valor: ruído de nome não
  // dispara o alarme, e qualquer mudança de código que mereça uma linha no CI
  // passa longe disso.
  noiseB: 256,
};

// §12, re-medido no worktree do merge em 17/08/2026. NÃO alterar sem decisão
// do coordenador: o delta em bytes de todo PR que toca `sdk/` sai daqui.
const SDK_BASELINE = { raw: 29_014, gzip: 9_595 };

const WIDGET_ENTRY = 'entrypoints/widget.js';

// Trava do Leaflet — o mapa é carregado por `import()` dinâmico
// (`dashboard/components-next/location/LocationPickerModal.vue:88-95`), e tem
// de continuar assim. São DUAS deteções, e a segunda existe porque a primeira
// tem um ponto cego que foi reproduzido com build real:
//
//   (i)  NOMINAL — `leaflet-*.js` no fecho estático de algum entrypoint. É o
//        que o aceite do bloco 0.5 pede, palavra por palavra.
//
//   (ii) POR CONTEÚDO — a assinatura do Leaflet dentro de QUALQUER arquivo do
//        fecho estático. Ao tornar o import estático, o Rollup NÃO recria o
//        chunk `leaflet-*.js`: ele inlina o Leaflet dentro do chunk que o
//        importa, e nenhum arquivo com "leaflet" no nome sobra no manifest.
//        Uma trava só nominal fica VERDE nesse caso — foi medido. As strings
//        abaixo são classes que o Leaflet escreve no DOM: sobrevivem à
//        minificação e ao rename de variável.
//
// A (ii) varre só JS. O CSS do Leaflet contém as mesmas classes, e ele entra
// no grafo por `import('leaflet/dist/leaflet.css')` — que é dinâmico e
// legítimo; varrer CSS produziria falso positivo sem acrescentar deteção.
const LEAFLET_RE = /(^|\/)leaflet[-.].*\.js$/i;
const LEAFLET_SIGNATURES = ['leaflet-container', 'leaflet-pane'];

// ── Args ────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};
const asJson = argv.includes('--json');
const DEFAULT_MANIFEST = 'public/vite/.vite/manifest.json';
const DEFAULT_SDK = 'public/packs/js/sdk.js';
const manifestArg = flag('manifest', DEFAULT_MANIFEST);
const sdkArg = flag('sdk', DEFAULT_SDK);
const manifestPath = path.resolve(manifestArg);
// O manifest mora em <assetsRoot>/.vite/manifest.json.
const assetsRoot = path.resolve(
  flag('assets-root', path.dirname(path.dirname(manifestPath)))
);
const sdkPath = path.resolve(sdkArg);
// Um gate provado contra artefato montado não está provado (§12.3). Medir
// fora dos caminhos do build é legítimo para comparar dois builds, mas o
// resultado não vale como gate — e a saída tem de dizer isso.
const offBuild = manifestArg !== DEFAULT_MANIFEST || sdkArg !== DEFAULT_SDK;

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
  v.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
const kib = v => `${dec2(v / 1024)} KiB`;
const signed = v => `${v >= 0 ? '+' : '−'}${n(Math.abs(v))} B`;
const pct = (delta, base) =>
  base === 0
    ? 'n/d'
    : `${delta >= 0 ? '+' : '−'}${dec2(Math.abs((delta / base) * 100))}%`;

const out = [];
const say = line => out.push(line);

// Falha classificada: `debt` já estava aqui e tem dono nomeado; `new` entrou
// agora e é de quem está lendo o vermelho. A distinção é o que impede o R17.
const failures = [];
const fail = (kind, title, detail) => failures.push({ kind, title, detail });
const debts = () => failures.filter(f => f.kind === 'debt');
const news = () => failures.filter(f => f.kind === 'new');

// Anotações do GitHub Actions: regressão nova em vermelho, dívida em amarelo.
// No CI o step falha nos dois casos; o que muda é o que salta aos olhos.
const ci = process.env.GITHUB_ACTIONS === 'true';
const annotate = () => {
  if (!ci) return;
  for (const f of news()) {
    process.stdout.write(
      `::error title=Regressão de peso — ${f.title}::${f.detail}\n`
    );
  }
  for (const f of debts()) {
    process.stdout.write(
      `::warning title=Dívida de peso conhecida — ${f.title}::${f.detail}\n`
    );
  }
};

// ── Execução ────────────────────────────────────────────────────────────────
if (!fs.existsSync(manifestPath)) {
  process.stderr.write(
    `widget-size: manifest não encontrado em ${manifestPath}\n` +
      `Rode \`bin/vite build\` (ou \`bundle exec rake assets:precompile\`) antes do gate.\n`
  );
  process.exit(2);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const report = { manifest: manifestPath, offBuild, checks: {} };

say('');
say('GATE DE PESO DO WIDGET — mede o GRAFO (fecho transitivo do manifest),');
say('não o chunk de entrada. PLANO-MESTRE bloco 0.5 · A13 · §12.3 · R17');
say('');
if (offBuild) {
  say('AVISO — medição fora dos caminhos do build (--manifest/--sdk).');
  say('        Serve para comparar dois builds; NÃO vale como gate.');
  say('');
}
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
const fontWeight = weigh(closure.assets);
const totalRaw = jsWeight.raw + cssWeight.raw;
const totalGzip = jsWeight.gzip + cssWeight.gzip;

const overCeiling = jsWeight.gzip - LIMITS.widgetGraphGzip; // > 0 = estourado
const vsBaseline = jsWeight.gzip - GRAPH_BASELINE.gzip; // > 0 = piorou
const regressed = vsBaseline > GRAPH_BASELINE.noiseB;
const improved = -vsBaseline > GRAPH_BASELINE.noiseB;

say(`entrada ............... ${WIDGET_ENTRY} → ${entry.file}`);
say('');
say('[1] GRAFO DO WIDGET — first-paint (entrada + imports estáticos, dedup)');
say(`    módulos JS ........ ${closure.js.size}`);
say(
  `    JS eager .......... ${n(jsWeight.raw).padStart(11)} B crus  ${n(jsWeight.gzip).padStart(9)} B gzip  (${kib(jsWeight.gzip)})`
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
  `    fontes .woff2 ..... ${n(fontWeight.raw).padStart(11)} B crus  (${closure.assets.size} arq., fora da régua — ver bloco 1.08)`
);
say('');
say(`    TETO (JS eager) ... ${n(LIMITS.widgetGraphGzip).padStart(9)} B gzip`);
say(`    medido ............ ${n(jsWeight.gzip).padStart(9)} B gzip`);

if (overCeiling > 0) {
  say(
    `    ESTOURO ........... ${signed(overCeiling).padStart(9)}   (${pct(overCeiling, LIMITS.widgetGraphGzip)} acima do teto)`
  );
  say('');
  const inherited = Math.min(
    overCeiling,
    GRAPH_BASELINE.gzip - LIMITS.widgetGraphGzip
  );
  if (regressed) {
    // Não dizer "isto não é regressão sua" na frente de um número que a
    // regressão inflou: separar quanto do estouro é herdado e quanto entrou.
    say(
      `    ▸ DESTE ESTOURO, ${signed(inherited)} JÁ EXISTIA — dívida conhecida da`
    );
    say('      §12.3, rastreada, com dono (bloco 1.08). Os outros');
    say(
      `      ${signed(overCeiling - inherited)} ENTRARAM COM A SUA MUDANÇA (ver logo abaixo).`
    );
  } else {
    say('    ▸ DÍVIDA CONHECIDA E RASTREADA — isto NÃO é regressão sua.');
    say(
      '      Este gate NASCE VERMELHO por decisão registrada antes da sua PR'
    );
    say('      (PLANO-MESTRE §12.3). O `size-limit` antigo dizia verde porque');
    say(
      `      media o chunk de entrada (${n(entryOnly.gzip)} B) em vez do grafo.`
    );
    say('      O teto NÃO se afrouxa para acomodar o número.');
  }
  say('');
  say('      QUEM DERRUBA: bloco 1.08 — `content` próprio do Tailwind para o');
  say('      widget (o CSS do widget tem hoje 1.692.256 B crus e 7');
  say('      `@font-face` que ninguém baixa); depois o 2.18, que fecha o JS');
  say('      eager em ≤ 150 KB gzip. Até um deles entrar, este passo fica');
  say('      vermelho — e é assim que foi combinado.');
  fail(
    'debt',
    'grafo do widget acima do teto',
    `${n(jsWeight.gzip)} B gzip > teto ${n(LIMITS.widgetGraphGzip)} B ` +
      `(${signed(overCeiling)}, ${pct(overCeiling, LIMITS.widgetGraphGzip)}). ` +
      (regressed
        ? `Desse estouro, ${signed(inherited)} é dívida herdada da §12.3 ` +
          `(dono: bloco 1.08) e ${signed(overCeiling - inherited)} entrou nesta mudança.`
        : `Dívida conhecida da §12.3; derrubada pelo bloco 1.08.`) +
      ` Linha de base de ${GRAPH_BASELINE.date}: ${n(GRAPH_BASELINE.gzip)} B ` +
      `(hoje ${signed(vsBaseline)}).`
  );
} else {
  say(
    `    FOLGA ............. ${n(-overCeiling).padStart(9)} B abaixo do teto`
  );
  say('');
  say('    ▸ A DÍVIDA DA §12.3 ACABOU. O grafo entrou no teto de 300 kB.');
  say('      Baixe GRAPH_BASELINE.gzip neste arquivo para o valor de hoje');
  say('      antes de fechar a PR, senão a régua de regressão fica frouxa em');
  say(`      ${n(GRAPH_BASELINE.gzip - jsWeight.gzip)} B.`);
}

say('');
say(
  `    linha de base ..... ${n(GRAPH_BASELINE.gzip)} B gzip  (${GRAPH_BASELINE.date}, ${GRAPH_BASELINE.where})`
);
say(
  `    contra a base ..... ${signed(vsBaseline)} (${pct(vsBaseline, GRAPH_BASELINE.gzip)})` +
    `   tolerância de ruído de build: ±${n(GRAPH_BASELINE.noiseB)} B`
);
if (regressed) {
  say('');
  say('    ▸ REGRESSÃO NOVA — O GRAFO PIOROU DEPOIS QUE O GATE NASCEU.');
  say('      Isto é seu, e é o que esta PR tem de resolver. A dívida herdada');
  say(
    `      era ${pct(GRAPH_BASELINE.gzip - LIMITS.widgetGraphGzip, LIMITS.widgetGraphGzip)} acima do teto; com a sua mudança são ` +
      `${pct(overCeiling, LIMITS.widgetGraphGzip)}.`
  );
  say('      Veja em qual módulo o peso entrou na lista abaixo.');
  fail(
    'new',
    'o grafo do widget cresceu',
    `${n(jsWeight.gzip)} B gzip contra a linha de base de ${GRAPH_BASELINE.date} ` +
      `(${n(GRAPH_BASELINE.gzip)} B): ${signed(vsBaseline)} (${pct(vsBaseline, GRAPH_BASELINE.gzip)}), ` +
      `acima da tolerância de ruído de ${n(GRAPH_BASELINE.noiseB)} B.`
  );
} else if (improved) {
  say(
    `    ▸ MELHOROU ${n(-vsBaseline)} B contra a base. Se for para valer, baixe ` +
      `GRAPH_BASELINE.gzip para ${n(jsWeight.gzip)} nesta PR.`
  );
}

say('');
say('    módulos do grafo, por peso gzip:');
for (const r of jsWeight.rows) {
  say(
    `      ${n(r.gzip).padStart(9)} B gzip  ${n(r.raw).padStart(9)} B crus  ${r.file}`
  );
}
for (const r of cssWeight.rows) {
  say(
    `      ${n(r.gzip).padStart(9)} B gzip  ${n(r.raw).padStart(9)} B crus  ${r.file}  [css]`
  );
}

report.checks.widgetGraph = {
  ok: overCeiling <= 0 && !regressed,
  modules: closure.js.size,
  jsRaw: jsWeight.raw,
  jsGzip: jsWeight.gzip,
  cssRaw: cssWeight.raw,
  cssGzip: cssWeight.gzip,
  totalRaw,
  totalGzip,
  entryRaw: entryOnly.raw,
  entryGzip: entryOnly.gzip,
  fontsRaw: fontWeight.raw,
  ceiling: LIMITS.widgetGraphGzip,
  overCeiling,
  baseline: GRAPH_BASELINE,
  vsBaseline,
  regressed,
  files: [...jsWeight.rows, ...cssWeight.rows.map(r => ({ ...r, css: true }))],
};

// ── [2] Leaflet: nominal + por conteúdo ─────────────────────────────────────
const entryKeys = Object.keys(manifest).filter(k => manifest[k].isEntry);
const nominalHits = [];
const contentHits = [];
const scanned = new Set();

for (const key of entryKeys) {
  const { js } = staticClosure(manifest, key);
  for (const file of js) {
    if (LEAFLET_RE.test(file)) nominalHits.push({ entry: key, file });
    if (scanned.has(file)) continue;
    scanned.add(file);
    const src = fs.readFileSync(path.join(assetsRoot, file), 'latin1');
    const found = LEAFLET_SIGNATURES.filter(s => src.includes(s));
    if (found.length === LEAFLET_SIGNATURES.length) {
      contentHits.push({ entry: key, file, signatures: found });
    }
  }
}

say('');
say('[2] LEAFLET FORA DO FIRST-PAINT — o mapa só por `import()` dinâmico');
say(`    entradas varridas . ${entryKeys.length}`);
say(`    arquivos varridos . ${scanned.size} (fecho estático de todas elas)`);
say('');
say('    (i)  nominal — `leaflet-*.js` no fecho estático');
if (nominalHits.length === 0) {
  say('         OK — nenhum');
} else {
  for (const h of nominalHits) {
    say(`         FALHA — ${h.file} é import ESTÁTICO de ${h.entry}`);
  }
}
say(
  `    (ii) por conteúdo — [${LEAFLET_SIGNATURES.join(', ')}] dentro do fecho`
);
say('         (o Rollup INLINA o Leaflet quando o import vira estático; a');
say('          trava nominal sozinha fica verde nesse caso — foi medido)');
if (contentHits.length === 0) {
  say('         OK — nenhum');
} else {
  for (const h of contentHits) {
    say(`         FALHA — ${h.file} carrega o Leaflet no fecho de ${h.entry}`);
  }
}

if (nominalHits.length || contentHits.length) {
  say('');
  say('    O mapa tem de continuar em `import()` dinâmico:');
  say('    dashboard/components-next/location/LocationPickerModal.vue:88-95.');
  // Um mesmo arquivo costuma disparar as duas travas. Listar o par
  // (arquivo, entrada) uma vez só, dizendo quais travas o pegaram.
  const by = new Map();
  const note = (h, trava) => {
    const k = `${h.file} ${h.entry}`;
    if (!by.has(k)) by.set(k, { ...h, travas: [] });
    by.get(k).travas.push(trava);
  };
  for (const h of nominalHits) note(h, 'nominal');
  for (const h of contentHits) note(h, 'conteúdo');
  const where = [...by.values()].map(
    h => `${h.file} em ${h.entry} (trava: ${h.travas.join(' + ')})`
  );
  fail(
    'new',
    'Leaflet voltou ao first-paint',
    `O Leaflet (~149 KB) entrou no fecho de imports ESTÁTICOS: ${where.join('; ')}. ` +
      `Ele tem de continuar em import() dinâmico ` +
      `(LocationPickerModal.vue:88-95) — só quem abre o seletor de local paga por ele.`
  );
}
report.checks.leaflet = {
  ok: nominalHits.length === 0 && contentHits.length === 0,
  scanned: scanned.size,
  nominalHits,
  contentHits,
};

// ── [3] sdk.js ──────────────────────────────────────────────────────────────
say('');
say('[3] sdk.js — a vantagem nº 1 (100% dos visitantes de todos os sites)');
if (!fs.existsSync(sdkPath)) {
  say(`    FALHA — ${sdkPath} não existe. Rode \`pnpm build:sdk\`.`);
  fail(
    'new',
    'sdk.js ausente',
    `${sdkPath} não existe; o gate não tem o que medir. Rode \`pnpm build:sdk\`.`
  );
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
      (rawOk
        ? `OK (folga ${n(LIMITS.sdkRaw - sdkRaw)} B)`
        : `FALHA (${signed(sdkRaw - LIMITS.sdkRaw)})`)
  );
  say(
    `    gzip .............. ${n(sdkGzip).padStart(9)} B   teto ${n(LIMITS.sdkGzip)} B   ` +
      (gzipOk
        ? `OK (folga ${n(LIMITS.sdkGzip - sdkGzip)} B)`
        : `FALHA (${signed(sdkGzip - LIMITS.sdkGzip)})`)
  );
  say(
    `    linha de base §12 . ${n(SDK_BASELINE.raw)} B crus / ${n(SDK_BASELINE.gzip)} B gzip`
  );
  say(
    `    DELTA ............. cru ${signed(dRaw)} (${pct(dRaw, SDK_BASELINE.raw)})   ` +
      `gzip ${signed(dGzip)} (${pct(dGzip, SDK_BASELINE.gzip)})`
  );
  say(
    `    (gzip medido como \`gzip -c <arquivo> | wc -c\`, o comando da §12; sem o` +
      ` FNAME do header são ${n(sdkGzipDet)} B)`
  );

  if (!rawOk) {
    fail(
      'new',
      'sdk.js estourou o teto cru',
      `${n(sdkRaw)} B crus > teto ${n(LIMITS.sdkRaw)} B (${signed(sdkRaw - LIMITS.sdkRaw)}). ` +
        `Contra a linha de base §12 (${n(SDK_BASELINE.raw)} B): ${signed(dRaw)} (${pct(dRaw, SDK_BASELINE.raw)}).`
    );
  }
  if (!gzipOk) {
    fail(
      'new',
      'sdk.js estourou o teto gzip',
      `${n(sdkGzip)} B gzip > teto ${n(LIMITS.sdkGzip)} B (${signed(sdkGzip - LIMITS.sdkGzip)}). ` +
        `Contra a linha de base §12 (${n(SDK_BASELINE.gzip)} B): ${signed(dGzip)} (${pct(dGzip, SDK_BASELINE.gzip)}). ` +
        `É o arquivo que 100% dos visitantes de todos os sites baixam (A13).`
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
// Separado em duas listas de propósito: um CI que só diz "vermelho" quando
// está sempre vermelho não é lido. Quem abre este log tem de saber, na
// primeira linha, se o vermelho é dele ou se já estava aqui (R17).
say('');
say('═══ VEREDITO ═══');
if (failures.length === 0) {
  say(
    'VERDE — teto do grafo, trava do Leaflet e os dois tetos do sdk.js passam.'
  );
} else {
  const nn = news();
  const dd = debts();
  say(
    nn.length
      ? `VERMELHO · ${nn.length} REGRESSÃO(ÕES) NOVA(S)` +
          (dd.length ? ` + ${dd.length} dívida(s) conhecida(s)` : '')
      : `VERMELHO · dívida conhecida apenas (${dd.length}) — nenhuma regressão nova`
  );
  say('');
  if (nn.length) {
    say(
      `  REGRESSÃO NOVA (${nn.length}) — entrou agora; é o que esta PR tem de resolver:`
    );
    for (const f of nn) {
      say(`    · ${f.title}`);
      say(`      ${f.detail}`);
    }
    say('');
  }
  if (dd.length) {
    say(
      `  DÍVIDA CONHECIDA (${dd.length}) — rastreada, com dono; NÃO é de quem está vendo:`
    );
    for (const f of dd) {
      say(`    · ${f.title}`);
      say(`      ${f.detail}`);
    }
    say('');
  }
  if (!nn.length) {
    say('  Nada do que está vermelho acima entrou com a sua mudança. O passo');
    say('  falha porque a dívida é real e permanece cobrada até o bloco que a');
    say('  derruba entrar — não porque a sua PR piorou alguma coisa.');
    say('');
  }
}

report.ok = failures.length === 0;
report.failures = failures;
report.newFailures = news().length;
report.knownDebt = debts().length;

process.stdout.write(
  asJson ? `${JSON.stringify(report, null, 2)}\n` : `${out.join('\n')}\n`
);
annotate();
process.exit(failures.length === 0 ? 0 : 1);
