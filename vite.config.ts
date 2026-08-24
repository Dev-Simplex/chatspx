import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';
import { chunkStats } from './vite.stats';

// O harness E2E do widget (`spec/e2e/widget/harness/widget-server.mjs`) sobe o Vite
// em middlewareMode com `root` na raiz do repositório e carrega ESTE arquivo como
// `configFile`. O `config()` do vite-plugin-ruby é mesclado por cima do config do
// usuário e reescreve `root` para o `sourceCodeDir` (`app/javascript`, em
// `config/vite.json`); com isso o pedido de `/app/javascript/entrypoints/widget.js`
// cai fora da raiz e o servidor devolve 404. Sob `TEST=true` o plugin sai e o `root`
// pedido pelo harness prevalece.
const isTestMode = process.env.TEST === 'true';

/* ────────────────────────────────────────────────────────────────────────────
 * VUE RUNTIME × VUE COMPLETO — bloco 2.18
 *
 * `vite.shared.ts` aponta `vue` para `vue/dist/vue.esm-bundler.js`, a build
 * COMPLETA: runtime + compilador de template. O compilador serve para compilar
 * `template:` em tempo de execução, e ele custa `@vue/compiler-dom` +
 * `@vue/compiler-core` — 168.582 B renderizados no fecho de first-paint do
 * widget, que NÃO compila template nenhum: todo `.vue` já sai compilado do
 * `@vitejs/plugin-vue`, em tempo de build.
 *
 * O ÚNICO consumidor de compilação em runtime de todo o `app/javascript` que
 * entra em bundle de produção é `portal/portalHelpers.js:86,104`, que monta
 * dois apps com `template:` string. Ele — e só ele — continua recebendo a
 * build completa.
 *
 * Os dois arquivos são cascas finas sobre o MESMO `@vue/runtime-dom`, então
 * conviver na mesma página não duplica o Vue: a completa apenas registra o
 * compilador (`registerRuntimeCompiler`) por cima do runtime compartilhado.
 *
 * Isto vale só para o build de produção. `vitest.config.ts` continua com o
 * alias de `vite.shared.ts`, porque dezenas de specs montam dublês com
 * `template: '<div />'` e precisam do compilador.
 * ──────────────────────────────────────────────────────────────────────────── */
const VUE_RUNTIME = 'vue/dist/vue.runtime.esm-bundler.js';
const VUE_COMPLETO = 'vue/dist/vue.esm-bundler.js';
const PRECISA_DO_COMPILADOR = '/app/javascript/portal/';

const alias = [
  {
    // `^vue$` e não a forma de objeto de propósito: com a chave `vue` o
    // `@rollup/plugin-alias` também casa `vue/dist/...` por prefixo, e a
    // substituição produziria caminho duplicado.
    find: /^vue$/,
    replacement: VUE_RUNTIME,
    async customResolver(_source: string, importer: string | undefined) {
      const alvo =
        importer && importer.includes(PRECISA_DO_COMPILADOR)
          ? VUE_COMPLETO
          : VUE_RUNTIME;
      const resolvido = await this.resolve(alvo, importer, { skipSelf: true });
      return resolvido || { id: alvo };
    },
  },
  ...Object.entries(aliases)
    .filter(([find]) => find !== 'vue')
    .map(([find, replacement]) => ({ find, replacement })),
];

/* ────────────────────────────────────────────────────────────────────────────
 * CHUNK DE VENDOR PRÓPRIO — MEDIDO E REJEITADO (bloco 2.18)
 *
 * A terceira frente do bloco no PLANO-MESTRE §2.2 é "chunk de vendor próprio".
 * Ela foi implementada e MEDIDA contra build real, e CUSTA bytes em vez de
 * economizar — por isso não está aqui, e este comentário existe para que a
 * próxima pessoa não repita o experimento achando que ninguém tentou.
 *
 * O agrupamento testado (conservador: `vendor-vue`, `vendor-i18n`,
 * `vendor-markdown`, `vendor-sanitize`, `vendor-http`, `vendor-routing`; sem
 * `date-fns` e sem `@sentry/*`, que o Rollup já divide por alcançabilidade):
 *
 *     sem manualChunks .... 289.629 B gzip de JS eager   (12 chunks)
 *     com manualChunks .... 316.365 B gzip de JS eager   (19 chunks)
 *     custo ...............  +26.736 B gzip  (+9,2%)
 *
 * SÃO DUAS CAUSAS, e as duas são estruturais:
 *
 *   1. gzip não é aditivo. Cada chunk é comprimido sozinho, com dicionário
 *      próprio; quebrar 12 arquivos em 19 tira do compressor a redundância
 *      entre eles. O gate cobra a SOMA dos gzip, que é o que a rede entrega.
 *   2. Agrupar por PACOTE desfaz o agrupamento por ALCANÇABILIDADE que o
 *      Rollup já faz. Um pacote usado tanto por caminho eager quanto por
 *      caminho lazy vira um chunk só, e o first-paint passa a baixar também
 *      a parte que só a rota lazy usava.
 *
 * O problema real que a frente queria resolver — nome de chunk que MENTE
 * (`Validators-*.js` continha `@sentry/core`, `vue-router` e `date-fns`) —
 * está resolvido por `scripts/widget-eager.check.mjs`, que lê `chunk.modules`
 * do Rollup e imprime o inventário por pacote. Diagnóstico sem custo de rede.
 * ──────────────────────────────────────────────────────────────────────────── */

export default defineConfig({
  plugins: [
    ...(isTestMode ? [] : [ruby()]),
    vue(vueOptions),
    yaml(),
    chunkStats(),
  ],
  optimizeDeps: {
    // Deps do canvas de Automações que leem `process.env.*`. Como o canvas é lazy-loaded,
    // sem incluí-las o vite dev não substitui `process` no pré-bundle e o chunk quebra com
    // "process is not defined" (Vue Flow via NODE_ENV; vue-shepherd via ES_BUILD). Só afeta
    // o DEV — o build de produção já substitui.
    include: [
      '@vue-flow/core',
      '@vue-flow/background',
      '@vue-flow/controls',
      '@vue-flow/minimap',
      'vue-shepherd',
    ],
    esbuildOptions: {
      define: {
        'process.env.ES_BUILD': 'false',
      },
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  // `dedupe` impede duas cópias de html2pdf.js no grafo (jsPDF/html2canvas entram
  // como transitivos), que produzem PDF em branco na exportação de conversas.
  resolve: { alias, dedupe: ['html2pdf.js'] },
});
