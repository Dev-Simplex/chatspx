/**
 * A lista de exclusão do watcher dos harness Vite.
 *
 * Os harness sobem o Vite com `root: repositoryRoot` — a raiz do repositório
 * inteiro, não `app/javascript` —, porque o widget importa de `app/`, de
 * `shared/` e de `spec/`. A consequência não intencional é que o chokidar
 * varre e vigia a árvore INTEIRA, e cada diretório vigiado custa um watch de
 * inotify.
 *
 * Medido nesta máquina: `tmp/` sozinho tem 14.240 diretórios no repositório
 * principal (relatório do Playwright, `test-results/`, caches de build). Cada
 * execução da suíte sobe DOIS servidores Vite, então são ~28.480 watches
 * gastos em diretórios que nenhum módulo do widget importa — e o limite é por
 * usuário, compartilhado com todas as sessões paralelas da máquina. É assim
 * que se chega ao `ENOSPC: System limit for number of file watchers reached`,
 * que o Playwright reporta como falha de boot do `webServer` — mensagem que
 * parece contenção de porta e não é.
 *
 * Cada entrada abaixo é um diretório que o Vite não precisa vigiar porque
 * NENHUM módulo do grafo do widget sai de lá:
 *
 *   · `tmp/`          — saída do Playwright e caches; escrito PELA suíte
 *                       enquanto ela roda, então vigiá-lo é convidar recarga
 *                       durante o próprio teste;
 *   · `node_modules/` — resolvido por `optimizeDeps`, não por HMR de fonte;
 *   · `public/`       — artefato de build (`public/vite`, `public/packs`), o
 *                       oposto de fonte;
 *   · `log/`          — log do Rails, escrito continuamente;
 *   · `.git/`         — banco de objetos do versionamento.
 *
 * `node_modules/` e `.git/` já estão no default do Vite; ficam explícitos aqui
 * porque passar `server.watch.ignored` SUBSTITUI o default em vez de somar a
 * ele — omiti-los aqui os traria de volta para dentro do watcher.
 */
export const WATCH_IGNORADO = [
  '**/tmp/**',
  '**/node_modules/**',
  '**/public/**',
  '**/log/**',
  '**/.git/**',
];

export default WATCH_IGNORADO;
