/* eslint-disable no-undef */
/**
 * ENTRAR UMA VEZ SO, e emprestar a sessao para todos os cenarios.
 *
 * Nao e economia de tempo: e a unica forma de a suite passar. O
 * `config/initializers/rack_attack.rb` tem
 *
 *     throttle('login/ip',    limit: 5,  period: 5.minutes)
 *     throttle('login/email', limit: 10, period: 15.minutes)
 *
 * e esta suite tem 6 cenarios. Entrando em cada `beforeEach`, o SEXTO login ja
 * estoura o teto por IP e o painel nunca carrega. Medido em 01/09/2026 contra
 * hmlchat: 2 de 6 verdes, e os 4 vermelhos reprovaram esperando a URL do painel
 * depois do login — reprovacao que se le como "o menu quebrou" e nao era.
 *
 * Com um login por RODADA sobra folga inteira dentro do teto, e o que cada
 * cenario mede volta a ser o menu.
 */
const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');

const DIRETORIO = path.resolve(__dirname, '../../../tmp/menu-contexto');
const ARQUIVO_DE_SESSAO = path.join(DIRETORIO, 'sessao.json');
const ARQUIVO_DA_CONTA = path.join(DIRETORIO, 'conta.json');

module.exports = async config => {
  const { baseURL } = config.projects[0].use;
  const email = process.env.E2E_AGENT_EMAIL;
  const senha = process.env.E2E_AGENT_PASSWORD;
  if (!email || !senha) {
    throw new Error(
      'Defina E2E_AGENT_EMAIL e E2E_AGENT_PASSWORD (usuario dedicado de QA).'
    );
  }

  fs.mkdirSync(DIRETORIO, { recursive: true });

  const navegador = await chromium.launch();
  const contexto = await navegador.newContext({ baseURL, locale: 'pt-BR' });
  const pagina = await contexto.newPage();

  await pagina.goto('/app/login', { waitUntil: 'domcontentloaded' });
  await pagina.waitForSelector('input[name="email_address"]', {
    timeout: 60_000,
  });
  await pagina.fill('input[name="email_address"]', email);
  await pagina.fill('input[type="password"]', senha);
  await pagina.click('button[type="submit"]');

  // A URL, e so a URL: o `POST /auth/sign_in` responde 200 em JSON e quem troca
  // a tela e o roteador, NO MESMO DOCUMENTO. `waitForURL` fica refem da semantica
  // de navegacao (medido: reprovou com 'load' e com 'commit', em rodadas onde o
  // mesmo login funcionava); `waitForFunction` so olha o `location.href`.
  try {
    await pagina.waitForFunction(
      () => /\/app\/accounts\/\d+/.test(window.location.href),
      null,
      { timeout: 90_000, polling: 500 }
    );
  } catch (erro) {
    const onde = pagina.url();
    await navegador.close();
    throw new Error(
      `O login nao chegou ao painel em 90s (a URL ficou em ${onde}). Se isto ` +
        'se repetir, confira o teto login/ip do Rack::Attack (5 por 5 min).'
    );
  }

  const contaId = pagina.url().match(/accounts\/(\d+)/)[1];
  await contexto.storageState({ path: ARQUIVO_DE_SESSAO });
  fs.writeFileSync(ARQUIVO_DA_CONTA, JSON.stringify({ contaId }));
  await navegador.close();
};

module.exports.ARQUIVO_DE_SESSAO = ARQUIVO_DE_SESSAO;
module.exports.ARQUIVO_DA_CONTA = ARQUIVO_DA_CONTA;
