const { defineConfig, devices } = require('@playwright/test');
const baseConfig = require('../../../playwright.config.js');

module.exports = defineConfig({
  ...baseConfig,
  testDir: __dirname,
  testMatch: /fixture\.sabotage\.js/,
  fullyParallel: false,
  retries: 0,
  reporter: [['list']],
  projects: [
    {
      name: 'widget-sabotage',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'http://127.0.0.1:8899',
      },
    },
  ],
});
