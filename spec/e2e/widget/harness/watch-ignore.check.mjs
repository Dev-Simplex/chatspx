/**
 * Prova de que `server.watch.ignored` dos harness FAZ EFEITO — medindo o
 * watcher de verdade, não conferindo a string no arquivo.
 *
 * Por que não basta um grep. `server.watch.ignored` é opção que o Vite pode
 * ignorar (nome errado, aninhamento errado, versão que a renomeou) sem emitir
 * aviso nenhum. Um teste que apenas encontrasse a chave no fonte ficaria verde
 * com o defeito vivo — que é exatamente o modo de falha desta base.
 *
 * Como a condição ruim é FORÇADA. Numa árvore recém-clonada, `tmp/` tem um
 * diretório só, então "watcher vigia tmp/" e "watcher não vigia tmp/" diferem
 * por 1 e a medição não distingue nada. Este check CRIA uma árvore descartável
 * de 200 diretórios em `tmp/__watch_probe__/`, `public/__watch_probe__/` e
 * `log/__watch_probe__/` antes de medir, e a apaga no fim. Sem a lista, esses
 * 200 aparecem no `getWatched()`; com a lista, nenhum aparece. É o mesmo
 * mecanismo que, com os 14.240 diretórios reais de `tmp/` no repositório
 * principal e dois servidores Vite por execução, esgota o inotify e derruba o
 * boot do `webServer` com `ENOSPC`.
 *
 * Uso: node spec/e2e/widget/harness/watch-ignore.check.mjs
 * Sai 0 se a lista faz efeito; 1 (com o motivo) se não faz.
 */
process.env.TEST = 'true';

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WATCH_IGNORADO } from './watch-ignore.mjs';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(currentDirectory, '../../../..');

const RAMOS = ['tmp', 'public', 'log'];
const POR_RAMO = 200;
const MARCA = '__watch_probe__';

const semear = () => {
  RAMOS.forEach(ramo => {
    for (let i = 0; i < POR_RAMO; i += 1) {
      const alvo = path.join(repositoryRoot, ramo, MARCA, `d${i}`);
      fs.mkdirSync(alvo, { recursive: true });
      fs.writeFileSync(path.join(alvo, 'arquivo.txt'), 'sonda\n');
    }
  });
};

const limpar = () => {
  RAMOS.forEach(ramo => {
    fs.rmSync(path.join(repositoryRoot, ramo, MARCA), {
      recursive: true,
      force: true,
    });
  });
};

const medir = async comIgnore => {
  const { createServer } = await import('vite');
  const vite = await createServer({
    root: repositoryRoot,
    configFile: path.join(repositoryRoot, 'vite.config.ts'),
    appType: 'custom',
    logLevel: 'silent',
    server: {
      hmr: false,
      middlewareMode: true,
      ...(comIgnore ? { watch: { ignored: WATCH_IGNORADO } } : {}),
    },
  });
  // O chokidar varre em background; sem esta espera a contagem sai pela metade
  // e o check mediria a velocidade do disco, não a lista de exclusão.
  await new Promise(resolve => {
    setTimeout(resolve, 15000);
  });
  const vigiados = Object.keys(vite.watcher.getWatched());
  await vite.close();
  return {
    total: vigiados.length,
    sondas: vigiados.filter(dir => dir.includes(MARCA)).length,
  };
};

const falhar = mensagem => {
  limpar();
  // eslint-disable-next-line no-console
  console.error(`FALHOU: ${mensagem}`);
  process.exit(1);
};

limpar();
semear();

const sem = await medir(false);
const com = await medir(true);

// eslint-disable-next-line no-console
console.log(
  `sem watch.ignored: ${sem.total} diretorios vigiados, ${sem.sondas} deles sob ${MARCA}\n` +
    `com watch.ignored: ${com.total} diretorios vigiados, ${com.sondas} deles sob ${MARCA}\n` +
    `reducao: ${sem.total - com.total} diretorios`
);

// A condição ruim precisa ter acontecido de verdade: se a sonda não foi vigiada
// nem SEM a lista, este check não distinguiria nada e passaria no vácuo.
if (sem.sondas < RAMOS.length * POR_RAMO) {
  falhar(
    `a condicao ruim nao foi reproduzida — sem a lista o watcher vigiou apenas ` +
      `${sem.sondas} das ${RAMOS.length * POR_RAMO} sondas. Sem isso o check nao mede nada.`
  );
}
if (com.sondas !== 0) {
  falhar(
    `watch.ignored nao fez efeito — ${com.sondas} diretorios de ${MARCA} continuam vigiados`
  );
}
if (com.total >= sem.total) {
  falhar(
    `watch.ignored nao reduziu a vigilancia: ${sem.total} -> ${com.total}`
  );
}

// A mesma lista tem de estar aplicada nos QUATRO harness — o check acima mede o
// módulo, e esta parte confere que os servidores realmente o consomem.
const harnessEsperados = [
  'harness/sdk-server.mjs',
  'harness/widget-server.mjs',
  'capture/harness.mjs',
  'citacao/harness.mjs',
];
const semAplicar = harnessEsperados.filter(relativo => {
  const fonte = fs.readFileSync(
    path.join(currentDirectory, '..', relativo),
    'utf8'
  );
  return !/watch:\s*\{\s*ignored:\s*WATCH_IGNORADO\s*\}/.test(fonte);
});
if (semAplicar.length) {
  falhar(`harness sem watch.ignored: ${semAplicar.join(', ')}`);
}

limpar();
// eslint-disable-next-line no-console
console.log('OK — a lista de exclusao do watcher faz efeito nos 4 harness.');
process.exit(0);
