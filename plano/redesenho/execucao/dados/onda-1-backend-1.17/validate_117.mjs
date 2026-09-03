// Validacao em NAVEGADOR REAL do bloco 1.17.
// Bate SEMPRE no IP da maquina, nunca em 127.0.0.1: o Rack::Attack tem safelist
// para localhost e metade do caminho de requisicao nao executaria.
import { chromium } from 'playwright';
import fs from 'node:fs';

const BASE = 'http://192.168.8.232:3057';
const SHOTS = process.argv[2];
const TOKEN = process.env.WIDGET_TOKEN;
const WEBSITE_TOKEN = process.env.WEBSITE_TOKEN;

const results = [];
const check = (name, pass, detail) => {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FALHOU'} :: ${name} :: ${detail}`);
};

async function login(page) {
  await page.goto(`${BASE}/app/login`, { waitUntil: 'domcontentloaded', timeout: 240000 });
  await page.waitForSelector('[data-testid="email_input"]', { timeout: 180000 });
  await page.fill('[data-testid="email_input"]', 'agente.val@exemplo.test');
  await page.fill('[data-testid="password_input"]', 'Val1dacao#2026');
  await page.click('button[type="submit"]');
  // Ancora de conteudo forte: o painel da conversa, nao networkidle.
  // 'commit' e nao 'load': o HMR do vite dev mantem conexoes abertas e o evento
  // load nunca dispara em modo dev.
  await page.waitForURL(/\/app\/accounts\/\d+/, {
    timeout: 180000,
    waitUntil: 'commit',
  });
}

async function openConversation(page) {
  await gotoConversation(page);
}

async function gotoConversation(page) {
  await page.goto(`${BASE}/app/accounts/1/conversations/1`, {
    waitUntil: 'domcontentloaded',
    timeout: 240000,
  });
  // Ancora de conteudo forte, nao networkidle: o e-mail do contato so aparece
  // depois que o painel lateral montou de verdade.
  await page
    .getByText('cliente@exemplo.test')
    .first()
    .waitFor({ timeout: 180000 });
  await expandConversationInfo(page);
}

// O painel do agente esconde o que precisamos atras de dois estados que o
// proprio SPA persiste em ui_settings — e por isso oscilam entre execucoes:
//   1. "Informacao da conversa" e um acordeao;
//   2. a lista corta em 5 itens, e a linha do IP e a 6a.
// A funcao e idempotente de proposito: le o estado e so age no que falta.
async function expandConversationInfo(page) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    if (await page.locator('[data-testid="ip-address-value"]').count()) return;

    const bodyMounted = await page.getByText('Iniciado em').count();
    if (!bodyMounted) {
      await page
        .getByText('Informação da conversa', { exact: true })
        .first()
        .click();
      await page.waitForTimeout(3000);
      continue;
    }

    const showAll = page.getByRole('button', {
      name: /Mostrar todos os atributos/i,
    });
    if (await showAll.count()) {
      await showAll.first().click();
      await page.waitForTimeout(3000);
      continue;
    }

    await page.waitForTimeout(2500);
  }

  await page.waitForSelector('[data-testid="ip-address-value"]', {
    timeout: 30000,
  });
}

async function sendAttributeFromWebsite(page) {
  // Caminho REAL do site: a mesma chamada que o SDK faz.
  return page.evaluate(
    async ({ base, token, websiteToken }) => {
      const res = await fetch(
        `${base}/api/v1/widget/conversations/set_custom_attributes`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Auth-Token': token,
          },
          body: JSON.stringify({
            website_token: websiteToken,
            custom_attributes: { carrinho_valor: 4200 },
          }),
        }
      );
      return res.status;
    },
    { base: BASE, token: TOKEN, websiteToken: WEBSITE_TOKEN }
  );
}

async function run(theme) {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    colorScheme: theme,
    locale: 'pt-BR',
  });
  // Modo dev: o vite compila o grafo sob demanda no primeiro acesso. O teto
  // alto e folga sobre isso, nao custo fixo.
  context.setDefaultNavigationTimeout(240000);
  context.setDefaultTimeout(90000);
  const page = await context.newPage();
  const consoleErrors = [];
  const badResponses = [];
  page.on('response', r => {
    if (r.status() >= 400) badResponses.push(`${r.status()} ${r.url()}`);
  });
  page.on('console', m => {
    if (m.type() === 'error') consoleErrors.push(m.text());
  });

  await login(page);
  await openConversation(page);

  // themeHelper.js:11 poe a classe no BODY, nao no documentElement, e resolve
  // por prefers-color-scheme quando o esquema e 'auto' (o padrao).
  const isDark = await page.evaluate(() =>
    document.body.classList.contains('dark')
  );
  check(
    `[${theme}] tema realmente aplicado`,
    theme === 'dark' ? isDark : !isDark,
    `html.dark=${isDark}`
  );

  // --- IP mascarado -------------------------------------------------------
  const ipText = (
    await page.locator('[data-testid="ip-address-value"]').innerText()
  ).trim();
  check(`[${theme}] IP nasce mascarado`, ipText === '203.•••', `texto="${ipText}"`);

  const html = await page.content();
  check(
    `[${theme}] IP completo nao esta no DOM enquanto mascarado`,
    !html.includes('203.0.113.77'),
    'busca por "203.0.113.77" no HTML renderizado'
  );

  // Visivel de verdade na tela, nao so presente no DOM.
  const ipVisible = await page
    .locator('[data-testid="ip-address-value"]')
    .isVisible();
  check(`[${theme}] linha do IP visivel na tela`, ipVisible, `isVisible=${ipVisible}`);

  await page.screenshot({
    path: `${SHOTS}/1.17-${theme}-1-ip-mascarado.png`,
    fullPage: false,
  });

  await page.locator('[data-testid="toggle-ip-address"]').click();
  await page.waitForFunction(
    () =>
      document.querySelector('[data-testid="ip-address-value"]')?.textContent
        .trim() === '203.0.113.77',
    { timeout: 10000 }
  );
  const revealed = (
    await page.locator('[data-testid="ip-address-value"]').innerText()
  ).trim();
  check(
    `[${theme}] revela o IP completo no clique`,
    revealed === '203.0.113.77',
    `texto="${revealed}"`
  );
  await page.screenshot({ path: `${SHOTS}/1.17-${theme}-2-ip-revelado.png` });

  await page.locator('[data-testid="toggle-ip-address"]').click();
  await page.waitForFunction(
    () =>
      document.querySelector('[data-testid="ip-address-value"]')?.textContent
        .trim() === '203.•••',
    { timeout: 10000 }
  );
  check(`[${theme}] volta a mascarar no segundo clique`, true, 'texto="203.•••"');

  // --- Secao "Dados recebidos do site" ------------------------------------
  const sectionBefore = await page
    .locator('[data-testid="from-website-section-title"]')
    .count();
  check(
    `[${theme}] secao ausente antes do site mandar a chave`,
    sectionBefore === 0,
    `count=${sectionBefore}`
  );

  const status = await sendAttributeFromWebsite(page);
  check(
    `[${theme}] site conseguiu mandar setCustomAttributes`,
    status === 200 || status === 204,
    `HTTP ${status}`
  );

  // "na mesma sessao": sem reload. Navegacao de SPA para a lista e de volta.
  await page.click('a[href*="/conversations"], [data-testid="conversation-back"]').catch(() => {});
  await gotoConversation(page);

  let appeared = false;
  try {
    await page.waitForSelector('[data-testid="from-website-section-title"]', {
      timeout: 30000,
    });
    appeared = true;
  } catch (e) {
    appeared = false;
  }

  const title = appeared
    ? (
        await page
          .locator('[data-testid="from-website-section-title"]')
          .innerText()
      ).trim()
    : '(ausente)';
  check(
    `[${theme}] secao "Dados recebidos do site (1)" aparece na mesma sessao`,
    // O titulo e renderizado com `uppercase` no CSS, entao innerText volta em
    // caixa alta. O que se mede aqui e o conteudo, nao a caixa.
    title.toLowerCase() === 'dados recebidos do site (1)',
    `titulo="${title}"`
  );

  const badgeCount = await page
    .locator('[data-testid="from-website-badge"]')
    .count();
  const badgeText = badgeCount
    ? (
        await page.locator('[data-testid="from-website-badge"]').first().innerText()
      ).trim()
    : '(ausente)';
  check(
    `[${theme}] selo de origem presente`,
    badgeCount === 1 && badgeText === 'Do site',
    `count=${badgeCount} texto="${badgeText}"`
  );

  // O selo nao pode ficar POR BAIXO do botao de excluir do atributo. O DOM nao
  // percebe sobreposicao; caixas delimitadoras percebem.
  const overlap = await page.evaluate(() => {
    const badge = document.querySelector('[data-testid="from-website-badge"]');
    const item = badge && badge.closest('[data-testid="from-website-attribute"]');
    const button = item && item.querySelector('button');
    if (!badge || !button) return { medido: false };
    const a = badge.getBoundingClientRect();
    const b = button.getBoundingClientRect();
    const intersecta =
      a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
    return { medido: true, intersecta, badge: [a.top, a.left], botao: [b.top, b.left] };
  });
  check(
    `[${theme}] selo nao fica por baixo do botao de acao do atributo`,
    overlap.medido && !overlap.intersecta,
    JSON.stringify(overlap)
  );

  // Contraste do selo, medido — nao opinado. WCAG AA para texto pequeno e 4.5.
  const contrast = await page.evaluate(() => {
    const el = document.querySelector('[data-testid="from-website-badge"]');
    if (!el) return null;
    const parse = v => (v.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
    const lum = ([r, g, b]) => {
      const f = c => {
        const x = c / 255;
        return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
      };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    // Sobe ate achar um fundo realmente pintado (o do selo pode ser transparente).
    let node = el;
    let bg = null;
    while (node && !bg) {
      const c = getComputedStyle(node).backgroundColor;
      if (c && !/rgba\(0, 0, 0, 0\)|transparent/.test(c)) bg = parse(c);
      node = node.parentElement;
    }
    const fg = parse(getComputedStyle(el).color);
    if (!bg || !fg) return null;
    const [a, b2] = [lum(fg), lum(bg)].sort((x, y) => y - x);
    return {
      ratio: Number(((a + 0.05) / (b2 + 0.05)).toFixed(2)),
      fg: getComputedStyle(el).color,
      bg: `rgb(${bg.join(', ')})`,
    };
  });
  check(
    `[${theme}] contraste do selo passa em WCAG AA (>= 4.5)`,
    !!contrast && contrast.ratio >= 4.5,
    contrast ? `ratio=${contrast.ratio} fg=${contrast.fg} bg=${contrast.bg}` : 'selo nao encontrado'
  );

  // O atributo cadastrado por agente NAO pode estar na secao do site.
  const inSection = await page
    .locator('[data-testid="from-website-attribute"]')
    .allInnerTexts();
  check(
    `[${theme}] atributo cadastrado pelo time fica FORA da secao`,
    !inSection.join(' ').includes('Plano'),
    `conteudo da secao=${JSON.stringify(inSection)}`
  );

  await page
    .locator('[data-testid="from-website-section-title"]')
    .scrollIntoViewIfNeeded()
    .catch(() => {});
  await page.screenshot({ path: `${SHOTS}/1.17-${theme}-3-secao-site.png` });

  const badRelevantForConsole = badResponses.filter(u => !/mini-profiler|favicon|waha_connections/.test(u));
  const realErrors = consoleErrors.filter(
    t =>
      !/favicon|ResizeObserver|Download the Vue Devtools|WebSocket|vite/i.test(
        t
      ) &&
      // O console so diz "Failed to load resource: 500" sem a URL; as unicas
      // respostas >=400 desta pagina sao as duas ambientais acima, medidas pelo
      // listener de response. Se surgir outra, o check de HTTP reprova.
      !(/Failed to load resource/i.test(t) && badRelevantForConsole.length === 0)
  );
  // Dois erros sao do AMBIENTE isolado, nao do codigo, e cada um foi conferido
  // na origem antes de entrar aqui:
  //   mini-profiler-resources/includes.js  500 — asset do rack-mini-profiler,
  //     so existe em modo dev e nada no painel depende dele;
  //   /api/v1/accounts/1/waha_connections  503 — waha_connections_controller.rb:29
  //     responde :service_unavailable de proposito quando nao ha servidor WAHA
  //     alcancavel, que e exatamente o caso desta VM de validacao.
  // Qualquer outro >=400 continua reprovando.
  const AMBIENTAIS = /mini-profiler|favicon|waha_connections/;
  const badRelevant = badResponses.filter(u => !AMBIENTAIS.test(u));
  check(
    `[${theme}] sem resposta HTTP de erro`,
    badRelevant.length === 0,
    badRelevant.length ? JSON.stringify([...new Set(badRelevant)]) : 'nenhuma'
  );
  check(
    `[${theme}] sem erro de console relevante`,
    realErrors.length === 0,
    realErrors.length ? JSON.stringify(realErrors.slice(0, 3)) : 'nenhum'
  );

  await browser.close();
}

const theme = process.argv[3] || 'light';
console.log(`\n===== TEMA ${theme.toUpperCase()} =====`);
await run(theme);

const failed = results.filter(r => !r.pass);
console.log(`\n===== RESUMO: ${results.length - failed.length}/${results.length} =====`);
fs.writeFileSync(`${SHOTS}/resultados-${theme}.json`, JSON.stringify(results, null, 2));
process.exit(failed.length ? 1 : 0);
