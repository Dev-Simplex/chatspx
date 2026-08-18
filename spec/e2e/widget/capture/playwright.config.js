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
  // 600 s pelo MESMO motivo do config raiz: o Vite em middlewareMode compila o
  // grafo do widget sob demanda, e em cache frio o aquecimento leva minutos. O
  // teto e folga sobre o medido, nao custo fixo — com o cache quente o hook
  // termina em segundos.
  timeout: 600000,
  reporter: [['list']],
  use: {
    ...devices['Desktop Chrome'],
    locale: 'pt-BR',
    video: 'off',
    trace: 'off',
    screenshot: 'off',
  },
});
