/*
 * SDK library build.
 *
 * vite-plugin-ruby pulls every entrypoint as input, but the SDK needs to ship
 * as a single IIFE file (`inlineDynamicImports: true`), which is incompatible
 * with multiple entrypoints. So the SDK gets its own pipeline:
 *
 *   vite build --config vite.lib.config.ts  → public/packs/js/sdk.js
 *
 * The `assets:precompile` rake task runs this alongside the main app build.
 */
import { defineConfig } from 'vite';
import path from 'path';
import { aliases } from './vite.shared';
import { chunkStats } from './vite.stats';
import { sdkCssMinify } from './vite.sdk-css';

export default defineConfig({
  plugins: [sdkCssMinify(), chunkStats()],
  // `sdk.js` tem DOIS tetos (A13) e é o CRU que aperta — o gzip nunca esteve
  // perto do limite. A trajetória do bloco 2.18, medida a cada passo:
  //
  //   45.229 B  ponto de partida (+5.229 acima do teto)
  //   42.969 B  −2.260 · `SDK_CSS` minificado no build + terser em 3 passes
  //   37.879 B  −5.090 · o pacote `md5` saiu (ver `sdk/dedupeHash.js`)
  //
  // com teto de 40.000 B: FOLGA de 2.121 B. E o gate é a trava — devolver o
  // `md5` ao arquivo estoura o cru de novo, então não existe caminho em que
  // ele volte em silêncio.
  //
  // Cada byte aqui é baixado por 100% dos visitantes de todos os sites de
  // todos os clientes, então a minificação é a mais agressiva que não muda
  // semântica:
  //
  //   · terser em 3 passes, em vez do esbuild padrão;
  //   · sem comentário legal no arquivo (a licença do js-cookie continua no
  //     `node_modules` e no `LICENSE` do pacote — o que sai daqui é a cópia
  //     dentro do bundle, e MIT não exige que ela viaje minificada);
  //   · `target` NÃO é mexido de propósito. Subir para `esnext` economizaria
  //     mais 425 B, mas o SDK roda no navegador do visitante do CLIENTE, que
  //     não escolhemos — trocar compatibilidade por bytes aqui é o negócio
  //     errado.
  esbuild: { legalComments: 'none' },
  build: {
    minify: 'terser',
    terserOptions: {
      compress: { passes: 3, unsafe_arrows: true, unsafe_methods: true },
      format: { comments: false },
    },
    rollupOptions: {
      output: {
        dir: 'public/packs',
        entryFileNames: chunkInfo =>
          chunkInfo.name === 'sdk' ? 'js/sdk.js' : '[name].js',
        inlineDynamicImports: true,
      },
    },
    lib: {
      entry: path.resolve(__dirname, './app/javascript/entrypoints/sdk.js'),
      formats: ['iife'],
      name: 'sdk',
    },
  },
  resolve: { alias: aliases },
});
