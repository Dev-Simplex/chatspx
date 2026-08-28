#!/usr/bin/env node
/* eslint-disable no-console -- Este arquivo é um corredor de linha de comando:
   a saída no console É o produto dele, lida por quem roda e pelo log do CI. Não
   é log esquecido em código de produção, que é o que a regra existe para pegar.
   Mesma isenção que os próprios `*.check.mjs` já carregam. */
/**
 * CORREDOR DOS VERIFICADORES DE NAVEGADOR — bloco 1.05.
 *
 * O PROBLEMA QUE ELE RESOLVE. O redesenho acumulou 21 arquivos `*.check.mjs`:
 * verificadores que sobem Chromium de verdade e medem `getComputedStyle` de
 * verdade, porque o defeito que perseguem é de CASCADE, de `:hover`, de
 * pseudo-elemento ou de geometria — coisas que jsdom não calcula e que um
 * `.spec.js` daria VERDE com o defeito vivo. Eles são a metade mais cara de
 * provar do plano.
 *
 * E até este bloco, `grep -rn "check.mjs" package.json .github/` devolvia ZERO.
 * Nenhum script npm, nenhum passo de CI. Vinte e um verificadores escritos com
 * cuidado, rodados uma vez cada um pelo autor do seu bloco, e depois nunca mais
 * — enquanto o `vitest` do lado que NÃO pega esses defeitos roda em todo PR.
 * Guarda que ninguém executa não é guarda; é documentação com sintaxe de teste.
 *
 * DECISÕES QUE PARECEM DETALHE E NÃO SÃO:
 *
 * 1. A LISTA VEM DE GLOB, NUNCA ESCRITA À MÃO. Uma lista literal envelhece no
 *    dia seguinte: o próximo bloco escreve o 22º verificador, esquece de
 *    registrá-lo aqui, e o corredor segue verde ignorando-o. O glob não tem como
 *    esquecer.
 *
 * 2. ZERO ARQUIVO ENCONTRADO É FALHA, não sucesso. É o modo de falhar mais
 *    perigoso deste arquivo: um glob que deixa de casar (pasta renomeada,
 *    extensão trocada, `cwd` errado) produziria "0 falhas" e sairia 0 — verde
 *    perfeito medindo absolutamente nada. O piso é declarado abaixo.
 *
 * 3. SAÍDA 2 CONTA COMO FALHA. Os verificadores desta base usam 2 para "não
 *    consegui medir" — tipicamente artefato de build ausente (`public/packs/js/
 *    sdk.js`, o manifest do Vite). "Não consegui medir" jamais pode sair como
 *    verde: é exatamente o estado em que o defeito passa. O corredor imprime a
 *    razão e o comando que produz o artefato, e falha.
 *
 * 4. SEQUENCIAL. Cada verificador sobe seu próprio Chromium; 21 em paralelo
 *    derrubam o runner do CI por memória, e o relato fica ilegível quando as
 *    saídas se intercalam.
 *
 *   node scripts/check-browser.mjs          (ou: pnpm run check:browser)
 *   node scripts/check-browser.mjs --list   só lista o que seria rodado
 *
 * Saída: 0 se todos passaram; 1 se algum falhou, não mediu, ou se o glob veio
 * vazio.
 */
import { readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Piso do glob. Não é o total exato de propósito — travar no número exato
// obrigaria a editar este arquivo a cada verificador novo, que é justamente o
// acoplamento que a decisão 1 evita. O que ele precisa pegar é o glob que
// DESABOU, e para isso um piso basta. Eram 21 quando o 1.05 escreveu isto.
const PISO = 15;

const IGNORAR = new Set(['node_modules', '.git', 'tmp', 'public', 'coverage']);

const encontrar = dir =>
  readdirSync(dir, { withFileTypes: true })
    .filter(e => !e.name.startsWith('.') && !IGNORAR.has(e.name))
    .flatMap(e => {
      const cheio = path.join(dir, e.name);
      if (e.isDirectory()) return encontrar(cheio);
      return e.name.endsWith('.check.mjs') ? [cheio] : [];
    });

const arquivos = encontrar(RAIZ)
  .filter(f => statSync(f).isFile())
  .map(f => path.relative(RAIZ, f))
  .sort();

if (process.argv.includes('--list')) {
  arquivos.forEach(f => console.log(f));
  process.exit(0);
}

if (arquivos.length < PISO) {
  console.error(
    `check:browser: o glob achou ${arquivos.length} verificador(es), abaixo do piso de ${PISO}.\n` +
      'Isso não é "tudo certo": é o glob quebrado. Verifique o cwd e a extensão `.check.mjs`.'
  );
  process.exit(1);
}

console.log(`check:browser — ${arquivos.length} verificadores\n`);

// `spawnSync`, e não uma corrida de promessas: cada verificador sobe seu próprio
// Chromium (decisão 4). `map` sobre um `spawnSync` executa em série do mesmo
// jeito, e sem `for`/`continue`.
const resultados = arquivos.map(arquivo => {
  const inicio = Date.now();
  const r = spawnSync(process.execPath, [arquivo], {
    cwd: RAIZ,
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  const segundos = ((Date.now() - inicio) / 1000).toFixed(1);
  const codigo = r.status ?? 1;
  const saida = `${r.stdout || ''}${r.stderr || ''}`;
  // O placar que os verificadores desta base imprimem no fim.
  const placar = (saida.match(/(\d+\/\d+) asserç/g) || []).pop() || '';

  const rotulo = { 0: '  ok    ', 2: 'NÃO MEDIU' }[codigo] || ' FALHOU  ';
  console.log(`${rotulo} ${arquivo}  ${placar} (${segundos}s)`);

  // A saída inteira do que quebrou, indentada — quem lê o log do CI precisa da
  // asserção e do número medido, não só do nome do arquivo.
  if (codigo !== 0) {
    console.log(
      saida
        .trimEnd()
        .split('\n')
        .map(l => `        │ ${l}`)
        .join('\n')
    );
    console.log('');
  }

  return { arquivo, codigo };
});

const falhas = resultados.filter(r => r.codigo !== 0 && r.codigo !== 2);
const naoMediram = resultados.filter(r => r.codigo === 2);
const quebrados = falhas.length + naoMediram.length;
console.log(
  `\n${arquivos.length - quebrados}/${arquivos.length} verificadores ok` +
    (falhas.length ? `  ·  ${falhas.length} falharam` : '') +
    (naoMediram.length ? `  ·  ${naoMediram.length} não mediram` : '')
);

if (naoMediram.length) {
  console.log(
    '\nOs que não mediram precisam do artefato construído antes. Nesta base:\n' +
      '  pnpm run build:sdk        → public/packs/js/sdk.js\n' +
      '  pnpm run build:tracking   → public/packs/js/tracking.js\n' +
      '  VITE_CHUNK_STATS=tmp/widget-eager-stats.json bin/vite build --force\n' +
      '`vite build` sozinho NÃO refaz public/packs/js/ — são configs separadas.'
  );
}

process.exit(quebrados ? 1 : 0);
