const { test: base, expect } = require('@playwright/test');

const test = base.extend({
  page: async ({ page }, use) => {
    const errors = [];

    page.on('pageerror', error => {
      errors.push(`pageerror: ${error.message}`);
    });
    page.on('console', message => {
      if (message.type() === 'error') {
        errors.push(`console.error: ${message.text()}`);
      }
    });
    page.on('requestfailed', request => {
      errors.push(
        `requestfailed: ${request.method()} ${request.url()} (${request.failure()?.errorText || 'unknown error'})`
      );
    });
    page.on('response', response => {
      if (response.status() >= 400) {
        errors.push(
          `HTTP ${response.status()}: ${response.request().method()} ${response.url()}`
        );
      }
    });

    await use(page);
    expect(errors, 'Erros capturados durante o teste').toEqual([]);
  },
});

module.exports = { test, expect };
