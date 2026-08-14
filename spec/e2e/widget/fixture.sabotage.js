const { test } = require('../fixtures');

test('sabotagem: console.error é capturado', async ({ page }) => {
  await page.setContent('<main>console sabotage</main>');
  await page.evaluate(() => {
    // eslint-disable-next-line no-console
    console.error('fixture-console-sabotage');
  });
});

test('sabotagem: pageerror é capturado', async ({ page }) => {
  const pageError = page.waitForEvent('pageerror');
  await page.setContent(
    '<script>Promise.reject(new Error("fixture-pageerror-sabotage"))</script>'
  );
  await pageError;
});

test('sabotagem: requestfailed é capturado', async ({ page }) => {
  const failedRequest = page.waitForEvent('requestfailed');
  await page
    .goto('http://127.0.0.1:1/fixture-request-sabotage')
    .catch(() => {});
  await failedRequest;
});

test('sabotagem: HTTP 500 é capturado', async ({ page }) => {
  await page.goto('http://127.0.0.1:8899/__sabotage__/500');
});
