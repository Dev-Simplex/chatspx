const { defineConfig, devices } = require('@playwright/test');

/**
 * Config PRÓPRIA das sabotagens do fixture (bloco 0.11), e ela **não herda** o
 * `playwright.config.js` da raiz — de propósito.
 *
 * O config raiz declara três `webServer` nas portas fixas 3038/3999/8899, que são recurso de
 * slot único disputado por várias trilhas. A versão anterior deste arquivo espalhava
 * `...baseConfig` e subia os três só para verificar um fixture. O mecanismo que prova a rede
 * de segurança não pode ser o que mais briga por porta: aqui não há `webServer` nenhum, e as
 * sabotagens usam `page.route`.
 *
 * Rodar:  node spec/e2e/widget/fixture-antierro.check.mjs
 */
module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /fixture\.sabotage\.js/,
  fullyParallel: false,
  retries: 0,
  timeout: 30000,
  reporter: [['json']],
  use: {
    ...devices['Desktop Chrome'],
    video: 'off',
    trace: 'off',
    screenshot: 'off',
  },
});
