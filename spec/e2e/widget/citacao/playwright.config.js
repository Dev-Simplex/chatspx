/**
 * Config PRÓPRIA do aceite de aparência do 6.03 — e ela NÃO herda de
 * `playwright.config.js` de propósito.
 *
 * O config raiz declara três `webServer` nas portas fixas 3038, 3999 e 8899, que são
 * slot único sob tranca do coordenador. Herdá-lo subiria os três só para medir a cor de
 * um rodapé. Aqui não há `webServer` nenhum: o próprio teste sobe o Vite numa porta
 * efêmera (ver `harness.mjs`), então nada disputa porta com trilha nenhuma.
 *
 * Rodar:  npx playwright test --config spec/e2e/widget/citacao/playwright.config.js
 */
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /citacao\.spec\.js/,
  fullyParallel: false,
  retries: 0,
  // 120 s, o MESMO teto do projeto `widget` do config raiz — de propósito, para que
  // este arquivo não passe aqui e falhe lá. Medido em 19/08/2026 nesta máquina: o
  // `beforeAll` (Vite + aquecimento dirigido) leva 24,9 s e o arquivo inteiro 31,6 s.
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
