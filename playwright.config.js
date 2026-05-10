// Playwright config for ChatSPX Copilot E2E suite (`spec/e2e/copilot/`).
//
// Runs against a locally-served dashboard. Override the base URL via
// `E2E_BASE_URL` (e.g. `http://localhost:3000` for `pnpm dev`,
// `https://hmlchat.simplexsolucoes.com.br` for homologação).
//
// The suite mocks Captain endpoints with `page.route()` so the tests do not
// require a real backend response — they only need the dashboard SPA to be
// reachable and able to load `/app`.
//
// SETUP REQUIRED (one-time, before first run):
//   1. Add `@playwright/test` to devDependencies:
//        pnpm add -D @playwright/test@^1.59.1
//   2. Install browsers:
//        pnpm exec playwright install chromium
//   3. (Optional) Seed an agent account for `loginAsAgent`:
//        bundle exec rails runner "Internal::SeedAccountJob.perform_now(...)"
//   4. Run:
//        E2E_BASE_URL=http://localhost:3000 pnpm exec playwright test

const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'spec/e2e',
  testMatch: /.*\.spec\.js/,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'tmp/playwright-report' }]],
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 8000,
    navigationTimeout: 15000,
    locale: 'pt-BR',
    timezoneId: 'America/Cuiaba',
  },
  projects: [
    {
      name: 'desktop-chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 720 },
      },
    },
    {
      name: 'mobile-chromium',
      use: {
        ...devices['Pixel 5'],
        viewport: { width: 375, height: 667 },
      },
      grep: /mobile|responsive/,
    },
  ],
});
