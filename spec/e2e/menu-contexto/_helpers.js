/* eslint-disable no-undef */
// Helpers da frente "menu de contexto da conversa".
//
// Estes testes rodam contra a INSTALACAO REAL (homologacao), nao contra um harness:
// o aceite e comportamento de navegador com backend, store, roteador e i18n de
// verdade. Vitest nao alcanca isso — o menu vive num `Teleport` para o `body`,
// abre por `contextmenu` e o efeito ("nao lida", prioridade) so existe depois que
// o servidor responde.

const fs = require('fs');
const path = require('path');
const { expect } = require('@playwright/test');
const { ARQUIVO_DA_CONTA } = require('./global-setup');

const TEMPO_PADRAO = 15_000;

/**
 * TRAVA DE ESCRITA. Os cenarios de "surte efeito" gravam de verdade (marcam nao
 * lida, mudam prioridade) e depois DESFAZEM. Isso e aceitavel em homologacao e
 * inaceitavel em qualquer outro lugar, entao o host precisa estar nomeado aqui —
 * ou declarado a mao em `E2E_ALLOW_HOST`. Sem isso, um `E2E_BASE_URL` apontado
 * para producao por descuido escreveria em conta de cliente.
 */
const HOSTS_COM_ESCRITA = [
  'hmlchat.simplexsolucoes.com.br',
  'localhost',
  '127.0.0.1',
];

const podeEscrever = baseURL => {
  const host = new URL(baseURL).hostname;
  return (
    HOSTS_COM_ESCRITA.includes(host) || process.env.E2E_ALLOW_HOST === host
  );
};

const exigirPermissaoDeEscrita = baseURL => {
  if (podeEscrever(baseURL)) return;
  throw new Error(
    `Este cenario GRAVA no backend e ${new URL(baseURL).hostname} nao esta na ` +
      'lista de hosts de homologacao. Rode contra homologacao ou declare ' +
      'E2E_ALLOW_HOST=<host> conscientemente.'
  );
};

/**
 * SERVIR O BUNDLE DA ARVORE, quando pedido.
 *
 * O `public/vite` da instalacao pode estar atras da arvore — foi o caso ao medir
 * esta regressao. Em vez de reconstruir a instalacao compartilhada (que outras
 * sessoes estao usando), com `E2E_VITE_DIR` o teste serve os assets do build
 * LOCAL por cima do HTML real. Sem a variavel, roda contra o bundle publicado,
 * que e como o teste deve rodar depois do deploy.
 *
 * ── O CASAMENTO, E O ERRO QUE ELE JA CUSTOU ────────────────────────────────────
 *
 * O HTML publicado pede `/vite/assets/v3app-<hash-velho>.js`; a arvore produziu
 * `v3app-<hash-novo>.js`. A primeira versao disto cortava o nome no ULTIMO hifen
 * para achar o par — e o hash do Vite tem 8 caracteres base64url, que PODEM conter
 * hifen (`Icon-DcJohv-I.js`). Nesses casos o corte devolvia `Icon-DcJohv`, o par
 * nao era achado, a requisicao caia no servidor e a pagina carregava METADE do
 * grafo velho por cima do novo. Sintoma medido: `SyntaxError: The requested module
 * './DashboardIcon-BmUtdl54.js' does not provide an export named 'cd'`.
 *
 * Agora o par sai dos DOIS manifestos, pela chave de origem que os dois
 * compartilham (o caminho do arquivo-fonte). Isso e exato e nao depende de
 * heuristica de nome. O corte por tamanho fixo de hash ficou so como ultimo
 * recurso, e a entrada precisa casar — senao `servirBundleLocal` levanta erro em
 * vez de deixar o teste medir, em silencio, o bundle publicado.
 */
const TAMANHO_DO_HASH = 8;
const TIPOS = {
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
};

/** `v3app-BpVDG0LX.js` -> `v3app.js`. So vale porque o hash tem tamanho fixo. */
const semHash = arquivo => {
  const ext = path.extname(arquivo);
  const base = path.basename(arquivo, ext);
  return `${base.slice(0, -(TAMANHO_DO_HASH + 1))}${ext}`;
};

const lerManifesto = raiz =>
  JSON.parse(
    fs.readFileSync(path.join(raiz, '.vite', 'manifest.json'), 'utf8')
  );

const indexarBuildLocal = raiz => {
  const dir = path.join(raiz, 'assets');
  const porNome = new Map();
  const porPrefixo = new Map();
  fs.readdirSync(dir).forEach(arquivo => {
    porNome.set(arquivo, path.join(dir, arquivo));
    const prefixo = semHash(arquivo);
    if (!porPrefixo.has(prefixo))
      porPrefixo.set(prefixo, path.join(dir, arquivo));
  });
  return { porNome, porPrefixo };
};

/** publicado -> local, pela chave de origem comum aos dois manifestos. */
const equivalencias = (publicado, local, viteDir) => {
  const mapa = new Map();
  const par = (arquivoPublicado, arquivoLocal) => {
    if (arquivoPublicado && arquivoLocal) {
      mapa.set(
        path.basename(arquivoPublicado),
        path.join(viteDir, arquivoLocal)
      );
    }
  };
  Object.entries(publicado).forEach(([chave, entrada]) => {
    const meu = local[chave];
    if (!meu) return;
    par(entrada.file, meu.file);
    (entrada.css || []).forEach((css, i) => par(css, (meu.css || [])[i]));
  });
  return mapa;
};

async function servirBundleLocal(page, viteDir, baseURL) {
  const local = lerManifesto(viteDir);
  const { porNome, porPrefixo } = indexarBuildLocal(viteDir);

  const resposta = await fetch(new URL('/vite/.vite/manifest.json', baseURL));
  if (!resposta.ok) {
    throw new Error(
      `Nao consegui ler o manifesto publicado (${resposta.status}); sem ele o ` +
        'casamento de chunks seria adivinhacao.'
    );
  }
  const publicado = await resposta.json();
  const equivalente = equivalencias(publicado, local, viteDir);

  // Sem esta trava, uma entrada nao mapeada faria a pagina carregar o bundle
  // PUBLICADO e o teste mediria o codigo de la achando que media o daqui.
  const entradasSemPar = Object.values(publicado)
    .filter(entrada => entrada.isEntry && entrada.file)
    .map(entrada => path.basename(entrada.file))
    .filter(arquivo => !equivalente.has(arquivo));
  if (entradasSemPar.length) {
    throw new Error(
      `Estas entradas do bundle publicado nao tem par no build local: ` +
        `${entradasSemPar.join(', ')}. Rode 'npx vite build' na arvore antes.`
    );
  }

  await page.route('**/vite/assets/**', async route => {
    const nome = decodeURIComponent(
      new URL(route.request().url()).pathname.split('/').pop()
    );
    const alvo =
      equivalente.get(nome) ||
      porNome.get(nome) ||
      porPrefixo.get(semHash(nome));

    if (!alvo) return route.fallback();
    return route.fulfill({
      status: 200,
      contentType: TIPOS[path.extname(nome)] || 'application/octet-stream',
      body: fs.readFileSync(alvo),
    });
  });
}

/**
 * A conta que o `global-setup.js` descobriu no unico login da rodada. Ninguem
 * entra de novo aqui: a sessao vem do `storageState` da config.
 */
const contaDaSessao = () => {
  if (!fs.existsSync(ARQUIVO_DA_CONTA)) {
    throw new Error(
      'Nao achei a conta da sessao. O globalSetup nao rodou — use a config ' +
        'desta pasta (menu-contexto.playwright.config.js).'
    );
  }
  return JSON.parse(fs.readFileSync(ARQUIVO_DA_CONTA, 'utf-8')).contaId;
};

/**
 * Abre a lista de conversas na aba "Todas" e espera os cartoes.
 * A aba padrao e "Minhas" — o usuario de QA nao tem conversa atribuida, entao
 * sem trocar de aba a lista vem vazia e o teste mediria a tela errada.
 */
async function abrirListaDeConversas(page, accountId) {
  await page.goto(`/app/accounts/${accountId}/dashboard`, {
    waitUntil: 'domcontentloaded',
  });
  await page
    .locator('button')
    .filter({ hasText: /^\s*Todas\s*\d*\s*$/ })
    .first()
    .waitFor({ timeout: 30_000 });
  await page.evaluate(() => {
    const alvo = [...document.querySelectorAll('button')].find(botao =>
      botao.innerText.trim().startsWith('Todas')
    );
    if (alvo) alvo.click();
  });

  const cartoes = page.locator('.conversation');
  await expect
    .poll(() => cartoes.count(), { timeout: 60_000 })
    .toBeGreaterThan(0);
  return cartoes;
}

/**
 * A raiz que o `ContextMenu` de ui/ teleporta para o body. Sao DOIS niveis, nao
 * um: o `TeleportWithDirection` interpoe um `<div dir="ltr|rtl">` para as classes
 * `ltr:`/`rtl:` continuarem valendo fora do container do app. Procurar
 * `body > div.fixed` nao acha nada e o teste reprova com "element(s) not found"
 * mesmo com o menu aberto na tela — falso vermelho, que e tao ruim quanto o verde.
 */
const menuDeContexto = page =>
  page.locator('body > div[dir] > div.fixed[tabindex="0"]');

/** Abre o menu com o botao direito, sobre o cartao pedido. */
async function abrirMenuNoCartao(page, cartao) {
  await cartao.scrollIntoViewIfNeeded();
  await cartao.click({ button: 'right' });
  const menu = menuDeContexto(page);
  await expect(menu).toBeVisible({ timeout: TEMPO_PADRAO });
  return menu;
}

/**
 * Qualquer linha do menu. Sao DUAS formas diferentes no DOM e confundi-las e
 * como um teste destes passa medindo metade: `menuItem.vue` e um
 * `div[role="button"]`; `menuItemWithSubmenu.vue` (Prioridade, Rotulo, Agente,
 * Time) e um `div.menu-with-submenu` SEM role.
 */
const itemDoMenu = (menu, texto) =>
  menu
    .locator('div[role="button"], div.menu-with-submenu')
    .filter({ hasText: texto })
    .first();

/**
 * Item com submenu (`menuItemWithSubmenu.vue`): o submenu so aparece no hover
 * (CSS `:hover .submenu`), entao e obrigatorio passar o ponteiro pelo pai antes
 * de procurar o filho.
 */
async function escolherNoSubmenu(menu, rotuloPai, rotuloFilho) {
  const pai = menu.locator('.menu-with-submenu').filter({ hasText: rotuloPai });
  await pai.first().hover();
  const filho = pai
    .first()
    .locator('.submenu div[role="button"]')
    .filter({ hasText: rotuloFilho })
    .first();
  await filho.waitFor({ state: 'visible', timeout: TEMPO_PADRAO });
  await filho.click();
}

const temNaoLida = cartao => cartao.locator('span.bg-n-teal-9').first();

/**
 * QUALQUER prioridade, nao so a urgente. `CardPriorityIcon` pinta as barras de
 * ambar em baixa/media/alta e de rubi em urgente. Procurar so pelo rubi levaria o
 * cenario a escolher uma conversa que ja tem prioridade ALTA e, ao "desfazer"
 * para "Nenhuma", apagaria a prioridade de verdade de uma conversa real.
 */
const temAlgumaPrioridade = cartao =>
  cartao.locator('svg rect.fill-n-amber-9, svg rect.fill-n-ruby-9').first();

const temPrioridadeUrgente = cartao =>
  cartao.locator('svg rect.fill-n-ruby-9').first();

module.exports = {
  TEMPO_PADRAO,
  abrirListaDeConversas,
  abrirMenuNoCartao,
  contaDaSessao,
  escolherNoSubmenu,
  exigirPermissaoDeEscrita,
  itemDoMenu,
  menuDeContexto,
  servirBundleLocal,
  temAlgumaPrioridade,
  temNaoLida,
  temPrioridadeUrgente,
};
