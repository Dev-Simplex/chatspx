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
  snapshotPathTemplate: '{testDir}/snapshots/{arg}{ext}',
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,
      animations: 'disabled',
    },
  },
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'tmp/playwright-report' }],
  ],
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
      testIgnore: /widget\//,
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 720 },
      },
    },
    {
      name: 'mobile-chromium',
      testIgnore: /widget\//,
      use: {
        ...devices['Pixel 5'],
        viewport: { width: 375, height: 667 },
      },
      grep: /mobile|responsive/,
    },
    {
      name: 'widget',
      testDir: 'spec/e2e/widget',
      fullyParallel: false,
      retries: 0,
      timeout: 120000,
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'http://127.0.0.1:8899',
        viewport: { width: 1280, height: 720 },
        video: 'off',
        launchOptions: {
          args: ['--disable-font-subpixel-positioning', '--disable-lcd-text'],
        },
      },
    },
  ],
  webServer: [
    {
      command: 'node spec/e2e/widget/harness/sdk-server.mjs',
      cwd: __dirname,
      url: 'http://127.0.0.1:3038/__ready',
      reuseExistingServer: false,
      timeout: 120000,
    },
    {
      command: 'node spec/e2e/widget/harness/widget-server.mjs',
      cwd: __dirname,
      url: 'http://127.0.0.1:3999/__ready',
      reuseExistingServer: false,
      timeout: 120000,
    },
    {
      command: 'node spec/e2e/widget/harness/host-server.mjs',
      cwd: __dirname,
      url: 'http://127.0.0.1:8899/__ready',
      reuseExistingServer: false,
      timeout: 120000,
    },
  ],
});
