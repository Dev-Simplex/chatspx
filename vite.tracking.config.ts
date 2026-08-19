/*
 * Bloco 5.07(c)/5.08 — build do COLETOR DE ORIGEM, separado do SDK de propósito.
 *
 * `vite.lib.config.ts` constrói o SDK como IIFE único com `inlineDynamicImports: true`.
 * Sob essa regra, um `import()` que o Rollup consiga resolver em tempo de build é INLINADO
 * dentro do `sdk.js` — ou seja, "sob demanda" não existiria e o coletor pesaria no arquivo
 * que 100% dos visitantes de todos os sites baixam.
 *
 * Por isso o coletor é um artefato próprio, em formato ES (o `import()` de runtime do
 * carregador precisa de um módulo de verdade do outro lado), no mesmo diretório público do
 * SDK. Quem o busca é `sdk/tracking/loader.js`, e só quando a inbox tem tracking ativo.
 *
 *   npx vite build --config vite.tracking.config.ts  → public/packs/js/tracking.js
 *
 * O `SdkCachePolicy` (bloco 5.07) cobre este caminho junto com o do SDK: os dois são
 * artefatos de caminho fixo, sem fingerprint, e teriam o mesmo problema de propagação.
 */
import { defineConfig } from 'vite';
import path from 'path';
import { aliases } from './vite.shared';

export default defineConfig({
  build: {
    // `emptyOutDir: false` porque o diretório é compartilhado com o build do SDK e os dois
    // rodam em sequência no `assets:precompile` — limpar aqui apagaria o `sdk.js`.
    emptyOutDir: false,
    rollupOptions: {
      output: { dir: 'public/packs', entryFileNames: 'js/tracking.js' },
    },
    lib: {
      entry: path.resolve(__dirname, './app/javascript/sdk/tracking/index.js'),
      formats: ['es'],
      fileName: () => 'js/tracking.js',
    },
  },
  resolve: { alias: aliases },
});
