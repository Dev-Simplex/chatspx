#!/usr/bin/env node
/**
 * Gate de peso dos assets de marca — bloco 1.08 do PLANO-MESTRE do redesenho.
 *
 * O que ele impede de voltar, e por que precisa de DUAS asserções:
 *
 *   1. TETO DE BYTES. `logo_thumbnail.svg` pesava 90.492 B e `logo.svg`
 *      98.279 B. Os dois são servidos em toda página do painel — o thumbnail
 *      como `<link rel="icon">` de `vueapp.html.erb` e de `portal.html.erb`.
 *      O aceite do bloco é `logo < 5 KB`.
 *
 *   2. NENHUM RASTER EMBUTIDO. O teto de bytes sozinho é um gate cego: os
 *      90 KB não vinham de path vetorial nenhum, vinham de dois PNG de
 *      1024x1024 em base64 dentro do `<svg>` — um de cor e outro de máscara.
 *      Um "SVG" assim não escala (o símbolo real tem 181 px de origem), e a
 *      forma de ele voltar é a mais banal que existe: alguém reexporta o
 *      arquivo num vetorizador e o vetorizador reembrulha o PNG. Um PNG
 *      pequeno o bastante passaria pelo teto de bytes e desfaria o bloco em
 *      silêncio. Por isso a segunda asserção não é redundante: ela cobra o
 *      MECANISMO, não o sintoma.
 *
 * Os arquivos cobrados são os quatro que o manual de marca declara em
 * `public/brand/manual-marca-spx.md` §4 (horizontal light/dark, símbolo light,
 * símbolo claro). Os `*1.svg` e `*2.svg` NÃO entram: `logo1`, `logo2`,
 * `logo_dark1`, `logo_dark2` e `logo_thumbnail1` são a identidade AZUL legada
 * (CorelDRAW/Chatwoot) que o manual proíbe usar, e `logo_thumbnail2` é o vetor
 * limpo de 709 B que já passa folgado. Cobrar arquivo que ninguém serve só
 * ensina a desligar gate.
 *
 * Uso:
 *   node scripts/brand-assets-size.mjs
 *   node scripts/brand-assets-size.mjs --json
 *
 * Saída: 0 se todos passam, 1 se qualquer um falha, 2 se o gate não conseguiu
 * medir (arquivo ausente) — porque "não consegui medir" nunca sai como verde.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIR = path.join(ROOT, 'public', 'brand-assets');

// 5 KB no sentido estrito (5.000 B), não 5 KiB: assim o número passa nas duas
// leituras de "5 KB" e ninguém precisa discutir a unidade para ler o gate.
const MAX_BYTES = 5000;

// `data:image/<algo>;base64` dentro do SVG. Cobre png, jpeg, gif e webp — o
// vetorizador escolhe o formato, e nenhum deles pode voltar para cá.
const RASTER = /data:image\/[a-z+]+;base64/i;

const FILES = [
  'logo.svg',
  'logo_dark.svg',
  'logo_thumbnail.svg',
  'logo_thumbnail-branca.svg',
];

// Peso de cada arquivo em 8568fb5832, antes do bloco 1.08. Serve para o
// relatório mostrar o delta: um gate que só diz "passou" fica cego para uma
// regressão que ainda cabe no teto.
const BASELINE = {
  'logo.svg': 98279,
  'logo_dark.svg': 98279,
  'logo_thumbnail.svg': 90492,
  'logo_thumbnail-branca.svg': 87371,
};

const json = process.argv.includes('--json');
const rows = [];
let missing = false;

for (const file of FILES) {
  const full = path.join(DIR, file);
  if (!fs.existsSync(full)) {
    rows.push({ file, erro: 'ausente' });
    missing = true;
    continue;
  }
  const buf = fs.readFileSync(full);
  const raster = RASTER.test(buf.toString('latin1'));
  rows.push({
    file,
    bytes: buf.length,
    teto: MAX_BYTES,
    antes: BASELINE[file] ?? null,
    raster,
    passa: buf.length <= MAX_BYTES && !raster,
  });
}

if (missing) {
  if (json) console.log(JSON.stringify({ status: 'nao_mediu', rows }, null, 2));
  else {
    console.error('GATE DE MARCA: não consegui medir — arquivo ausente:');
    for (const r of rows) if (r.erro) console.error(`  ${r.file}: ${r.erro}`);
  }
  process.exit(2);
}

const falhas = rows.filter(r => !r.passa);

if (json) {
  console.log(
    JSON.stringify(
      { status: falhas.length ? 'falha' : 'ok', maxBytes: MAX_BYTES, rows },
      null,
      2
    )
  );
} else {
  console.log(
    `Gate de peso dos assets de marca — teto ${MAX_BYTES} B por arquivo\n`
  );
  for (const r of rows) {
    const delta = r.antes
      ? ` (antes ${r.antes} B, −${(100 * (1 - r.bytes / r.antes)).toFixed(1)}%)`
      : '';
    console.log(
      `  ${r.passa ? 'OK  ' : 'FALHA'} ${r.file.padEnd(26)} ${String(r.bytes).padStart(6)} B${delta}` +
        (r.raster ? '  ← raster embutido (data:image;base64)' : '')
    );
  }
  if (falhas.length) {
    console.error(
      `\n${falhas.length} arquivo(s) reprovado(s). O teto de 5 KB é aceite do bloco 1.08 ` +
        `do PLANO-MESTRE e não se afrouxa: o símbolo cabe em vetor puro.`
    );
  }
}

process.exit(falhas.length ? 1 : 0);
