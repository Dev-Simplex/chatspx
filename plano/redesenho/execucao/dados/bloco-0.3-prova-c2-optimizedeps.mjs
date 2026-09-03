/*
 * Mecanismo de aceite do §C2 (optimizeDeps do canvas de Automações).
 *
 * COMO RODAR (de dentro do worktree que se quer verificar, não daqui):
 *   cd /caminho/do/worktree
 *   node plano/redesenho/execucao/dados/bloco-0.3-prova-c2-optimizedeps.mjs
 *   # ou, se o plano estiver em outro repo:
 *   node /home/chatwoot/chatwoot/plano/redesenho/execucao/dados/bloco-0.3-prova-c2-optimizedeps.mjs
 * Ele usa process.cwd() como root, então o diretório atual TEM de ser o worktree.
 * Sai com 0 se passou, 1 se falhou. Não abre porta nenhuma (middlewareMode).
 *
 * O bug original: `@vue-flow/*` e `vue-shepherd` só são importados DENTRO do chunk
 * lazy do canvas. Sem `optimizeDeps.include`, o Vite não os pré-bundla no boot do
 * dev server; eles chegam ao browser como ESM cru de node_modules, com
 * `process.env.NODE_ENV` / `process.env.ES_BUILD` literais, e o chunk morre com
 * "process is not defined".
 *
 * Este script sobe o MESMO config em modo dev (middlewareMode, sem abrir porta,
 * para não competir com nada) e afirma VALORES:
 *   1. o config resolvido lista as 5 deps em optimizeDeps.include
 *   2. o optimizer materializou o pré-bundle de cada uma em node_modules/.vite/deps
 *   3. o pré-bundle NÃO contém `process.env.NODE_ENV` nem `process.env.ES_BUILD`
 *      crus — que é exatamente o que causava o erro em runtime
 */
import path from 'node:path';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

// O script mora no scratchpad, fora do repo, então `import 'vite'` não resolve —
// carregamos o vite do node_modules do worktree por caminho absoluto.
const root = process.cwd();
const { createServer } = await import(
  pathToFileURL(path.join(root, 'node_modules/vite/dist/node/index.js')).href
);
const DEPS = [
  '@vue-flow/core',
  '@vue-flow/background',
  '@vue-flow/controls',
  '@vue-flow/minimap',
  'vue-shepherd',
];

const server = await createServer({
  configFile: path.join(root, 'vite.config.ts'),
  mode: 'development',
  logLevel: 'warn',
  server: { middlewareMode: true, hmr: false },
});

const included = server.config.optimizeDeps?.include ?? [];
console.log('1) optimizeDeps.include resolvido =', JSON.stringify(included));
const faltando = DEPS.filter(d => !included.includes(d));
console.log(
  faltando.length === 0
    ? '   OK: as 5 deps do canvas estão no include'
    : `   FALHA: ausentes -> ${faltando.join(', ')}`
);

const define = server.config.optimizeDeps?.esbuildOptions?.define ?? {};
console.log(
  '2) esbuildOptions.define["process.env.ES_BUILD"] =',
  JSON.stringify(define['process.env.ES_BUILD']),
  define['process.env.ES_BUILD'] === 'false' ? '  OK' : '  FALHA'
);

// Força o optimizer a rodar e esperar o resultado.
await server.listen?.().catch(() => {});
const optimizer = server.environments?.client?.depsOptimizer ?? null;
if (optimizer?.scanProcessing) await optimizer.scanProcessing;
// O optimizer escreve o metadata assim que termina; damos a ele um teto de tempo.
const depsDir = path.join(root, 'node_modules/.vite/deps');
const metaPath = path.join(depsDir, '_metadata.json');
const deadline = Date.now() + 180000;
const esperar = async () => {
  while (Date.now() < deadline) {
    if (fs.existsSync(metaPath)) {
      const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      if (DEPS.every(d => meta.optimized?.[d])) return meta;
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  return fs.existsSync(metaPath)
    ? JSON.parse(fs.readFileSync(metaPath, 'utf8'))
    : null;
};
const meta = await esperar();

console.log('3) pré-bundle materializado + `process.env` substituído:');
let todasOk = true;
for (const dep of DEPS) {
  const entrada = meta?.optimized?.[dep];
  if (!entrada) {
    console.log(`   ${dep}: FALHA — não consta em _metadata.json`);
    todasOk = false;
    continue;
  }
  const arquivo = path.join(depsDir, path.basename(entrada.file));
  if (!fs.existsSync(arquivo)) {
    console.log(`   ${dep}: FALHA — ${entrada.file} não existe em disco`);
    todasOk = false;
    continue;
  }
  const codigo = fs.readFileSync(arquivo, 'utf8');
  const nodeEnvCru = codigo.includes('process.env.NODE_ENV');
  const esBuildCru = codigo.includes('process.env.ES_BUILD');
  const ok = !nodeEnvCru && !esBuildCru;
  if (!ok) todasOk = false;
  console.log(
    `   ${dep}: ${path.basename(entrada.file)} ` +
      `(${fs.statSync(arquivo).size} B) ` +
      `process.env.NODE_ENV cru=${nodeEnvCru} process.env.ES_BUILD cru=${esBuildCru} ` +
      `${ok ? 'OK' : 'FALHA'}`
  );
}

await server.close();
const veredito = faltando.length === 0 && todasOk;
console.log(`\nVEREDITO §C2: ${veredito ? 'PASSOU' : 'FALHOU'}`);
process.exit(veredito ? 0 : 1);
