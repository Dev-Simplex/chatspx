import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

// O harness E2E do widget (`spec/e2e/widget/harness/widget-server.mjs`) sobe o Vite
// em middlewareMode com `root` na raiz do repositório e carrega ESTE arquivo como
// `configFile`. O `config()` do vite-plugin-ruby é mesclado por cima do config do
// usuário e reescreve `root` para o `sourceCodeDir` (`app/javascript`, em
// `config/vite.json`); com isso o pedido de `/app/javascript/entrypoints/widget.js`
// cai fora da raiz e o servidor devolve 404. Sob `TEST=true` o plugin sai e o `root`
// pedido pelo harness prevalece.
const isTestMode = process.env.TEST === 'true';

export default defineConfig({
  plugins: isTestMode
    ? [vue(vueOptions), yaml()]
    : [ruby(), vue(vueOptions), yaml()],
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
  resolve: { alias: aliases, dedupe: ['html2pdf.js'] },
});
