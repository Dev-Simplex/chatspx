// Config propria da tela de configuracao da caixa de entrada, para nao
// disputar o `playwright.config.js` do repositorio com as outras trilhas.
const path = require('path');
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /.*\.spec\.js/,
  fullyParallel: false,
  retries: 0,
  timeout: 60000,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:3071',
    locale: 'pt-BR',
    timezoneId: 'America/Cuiaba',
    viewport: { width: 1280, height: 900 },
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop-chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: [
    {
      command: 'node spec/e2e/inbox-config/harness/inbox-config-server.mjs',
      cwd: path.resolve(__dirname, '../../..'),
      url: 'http://127.0.0.1:3071/__ready',
      // FALSE de proposito: um servidor ja no ar nesta porta pode ser de outra
      // worktree — o `repositoryRoot` do harness vem do `import.meta.url` dele,
      // nao do meu. Reaproveitar mediria o codigo do vizinho.
      reuseExistingServer: false,
      timeout: 600000,
    },
  ],
});
