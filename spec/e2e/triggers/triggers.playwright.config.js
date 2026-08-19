// Config própria da tela de gatilhos (bloco 4.04), para não disputar o
// `playwright.config.js` do repositório com as outras trilhas em execução.
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
    baseURL: 'http://127.0.0.1:3062',
    locale: 'pt-BR',
    timezoneId: 'America/Cuiaba',
    viewport: { width: 1440, height: 900 },
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop-chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: [
    {
      command: 'node spec/e2e/triggers/harness/triggers-server.mjs',
      cwd: path.resolve(__dirname, '../../..'),
      url: 'http://127.0.0.1:3062/__ready',
      reuseExistingServer: true,
      timeout: 600000,
    },
  ],
});
