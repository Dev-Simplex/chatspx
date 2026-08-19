/**
 * Config PRÓPRIA do aceite do 4.03 — e ela NÃO herda de `playwright.config.js`
 * de propósito.
 *
 * O config raiz declara três `webServer` nas portas fixas 3038, 3999 e 8899, que
 * são recurso disputado por várias trilhas ao mesmo tempo. Herdá-lo subiria os
 * três só para medir a largura de um formulário. Aqui não há `webServer` nenhum:
 * o próprio teste sobe o Vite numa porta efêmera (ver `harness.mjs`).
 *
 * Rodar:  npx playwright test --config spec/e2e/widget/capture/playwright.config.js
 */
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /captureWidth\.spec\.js/,
  fullyParallel: false,
  retries: 0,
  // 120 s, o MESMO teto do projeto `widget` do config raiz — de propósito, para que este
  // arquivo não passe aqui e falhe lá. Procedência do número: com o aquecimento dirigido
  // (ver `harness.mjs`), medido em 18/08/2026 nesta máquina com outras trilhas ativas, o
  // `beforeAll` leva **22,4 s** e o fluxo inteiro **33,2 s**. A folga é de ~3,5x sobre o
  // medido. Se um dia estourar, o conserto é medir de novo — não subir o teto.
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
