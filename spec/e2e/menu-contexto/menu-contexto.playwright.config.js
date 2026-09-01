// Config propria da frente "menu de contexto da conversa", para nao disputar o
// `playwright.config.js` da raiz com as outras trilhas — e, sobretudo, para nao
// arrastar os tres `webServer` do harness do widget, que esta suite nao usa: aqui
// o alvo e a instalacao real, apontada por `E2E_BASE_URL`.
//
// Como rodar (homologacao):
//   E2E_BASE_URL=https://hmlchat.simplexsolucoes.com.br \
//   E2E_AGENT_EMAIL=... E2E_AGENT_PASSWORD=... \
//   npx playwright test --config spec/e2e/menu-contexto/menu-contexto.playwright.config.js
//
// Para medir o codigo da ARVORE quando o bundle publicado esta atras dela,
// acrescente E2E_VITE_DIR=<worktree>/public/vite (ver `_helpers.js`).
const { defineConfig, devices } = require('@playwright/test');
const { ARQUIVO_DE_SESSAO } = require('./global-setup');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /.*\.spec\.js/,
  // Um login por rodada, e nao um por cenario: o Rack::Attack corta o sexto
  // (`login/ip`, 5 por 5 min). Ver o cabecalho de `global-setup.js`.
  globalSetup: require.resolve('./global-setup'),
  // Serial: os cenarios de escrita gravam e desfazem na MESMA conversa. Em
  // paralelo um desfaria o efeito que o outro acabou de medir.
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 120_000,
  reporter: [['list']],
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:3000',
    storageState: ARQUIVO_DE_SESSAO,
    locale: 'pt-BR',
    timezoneId: 'America/Cuiaba',
    viewport: { width: 1400, height: 900 },
    screenshot: 'only-on-failure',
    trace: 'off',
    actionTimeout: 15_000,
    navigationTimeout: 45_000,
  },
  projects: [
    {
      name: 'claro',
      use: { ...devices['Desktop Chrome'], colorScheme: 'light' },
      grepInvert: /tema escuro/,
    },
    {
      name: 'escuro',
      use: { ...devices['Desktop Chrome'], colorScheme: 'dark' },
      // So o cenario de tema. Os de escrita rodam uma vez, no projeto claro: o
      // que muda no escuro e a pintura, nao a chamada — repetir a gravacao nos
      // dois temas dobraria a mexida no backend sem medir nada novo.
      grep: /tema escuro/,
    },
  ],
});
