/**
 * Config PRÓPRIA do aceite de aparência do 4.22 — não herda do `playwright.config.js`
 * raiz de propósito: aquele sobe os três servidores do harness do widget (3038/3999/
 * 8899), que são slot único sob tranca e servem outra superfície. Aqui o próprio teste
 * sobe o Vite numa porta efêmera.
 *
 * Rodar: npx playwright test --config spec/e2e/dashboard/modo-antigo/playwright.config.js
 */
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /modoAntigo\.spec\.js/,
  fullyParallel: false,
  retries: 0,
  timeout: 120000,
  reporter: [['list']],
  use: {
    ...devices['Desktop Chrome'],
    locale: 'pt-BR',
    video: 'off',
    trace: 'off',
    screenshot: 'off',
  },
});
