/// <reference types="vitest" />
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [vue(vueOptions), yaml()],
  resolve: { alias: aliases },
  // As MESMAS flags que `vite.config.ts` define no build de produção. Sem elas
  // aqui a suíte mediria uma configuração de `vue-i18n` que não é a que vai ao
  // ar, e um spec verde não diria nada sobre o bundle real. Foi assim que a
  // `__VUE_I18N_LEGACY_API__: false` foi reprovada: alinhar os dois lados fez
  // `memoDaLinha.spec.js` cair, e a queda era verdadeira.
  define: {
    __VUE_I18N_PROD_DEVTOOLS__: 'false',
    __INTLIFY_PROD_DEVTOOLS__: 'false',
  },
  test: {
    environment: 'jsdom',
    include: ['app/**/*.{test,spec}.?(c|m)[jt]s?(x)'],
    coverage: {
      reporter: ['lcov', 'text'],
      include: ['app/**/*.js', 'app/**/*.vue'],
      exclude: [
        'app/**/*.@(spec|stories|routes).js',
        '**/specs/**/*',
        '**/i18n/**/*',
      ],
    },
    globals: true,
    outputFile: 'coverage/sonar-report.xml',
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
    server: {
      deps: {
        inline: ['tinykeys', '@material/mwc-icon'],
      },
    },
    setupFiles: ['fake-indexeddb/auto', 'vitest.setup.js'],
    mockReset: true,
    clearMocks: true,
  },
});
