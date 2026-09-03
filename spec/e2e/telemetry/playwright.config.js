/**
 * Config PRÓPRIO do bloco 2.13, separado do `playwright.config.js` da raiz.
 *
 * Por que não reaproveitar o da raiz: o projeto `widget` de lá declara três
 * `webServer` em portas FIXAS (3038/3999/8899), que são recurso de slot único
 * disputado por várias trilhas. Carregar aquele config — mesmo para rodar um
 * arquivo que não usa o harness — subiria os três servidores e tomaria as
 * portas de quem estiver com a janela.
 *
 * Aqui não há `webServer` nenhum: o servidor deste bloco sobe dentro do
 * processo do teste, em porta efêmera (ver `harness/hostServer.js`).
 */
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /.*\.spec\.js/,
  fullyParallel: false,
  retries: 0,
  timeout: 60000,
  reporter: [['list']],
  use: {
    ...devices['Desktop Chrome'],
    viewport: { width: 1280, height: 720 },
    locale: 'pt-BR',
    trace: 'off',
    video: 'off',
    screenshot: 'off',
    actionTimeout: 8000,
    navigationTimeout: 15000,
  },
});
