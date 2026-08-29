/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * A DEGRADAÇÃO POR FAMILIARIDADE, EM NAVEGADOR REAL — bloco 4.19.
 *
 * §4 da Onda 3, item 2c, é nominal deste bloco e termina com sete palavras que
 * nenhum spec em jsdom satisfaz:
 *
 *   "Verificado em navegador real, com o cookie inspecionado — não por mock."
 *
 * `specs/approach.spec.js` cobre a mesma escada em jsdom e está verde. Ele não
 * substitui este arquivo, e a diferença não é de rigor — é de SUJEITO:
 *
 *   · em jsdom o cookie é uma string que `js-cookie` guarda e devolve. Nada
 *     valida `Secure`, nada valida `SameSite`, nada valida prazo, e um cookie
 *     que o Chromium DESCARTARIA volta a ser lido normalmente. Aqui o cookie é
 *     inspecionado no JAR DO NAVEGADOR (`context.cookies()`), que é o mesmo
 *     lugar de onde o Chromium o lê de volta na visita seguinte: se ele fosse
 *     recusado, a escada inteira desabaria em vez de passar;
 *   · em jsdom "visita" é `vi.resetModules()`. Aqui é `page.goto` de verdade:
 *     documento novo, `window` novo, módulo reexecutado, e o cookie
 *     sobrevivendo por conta do navegador, não por conta do teste;
 *   · em jsdom "converter" era `IFrameHelper` chamado na mão. Aqui a conversão
 *     entra pela PONTE REAL — um `<iframe>` de verdade faz `postMessage` para o
 *     host, o `onPostMessage` real confere a origem e só então o cookie zera. O
 *     controle cross-origin abaixo prova que essa conferência está ligada;
 *   · a altura de "grande" e "pequeno" é medida por CASCATA. jsdom não calcula
 *     caixa, então lá os dois níveis só se distinguem por `className` — que é a
 *     causa, nunca o efeito que o visitante vê.
 *
 * O QUE É O SUJEITO AQUI
 *
 * `IFrameHelper.montarTeaserSeConfigurado`, empacotado pelo Vite com o grafo
 * REAL (`teaser.js`, `tracking/approach.js`, `cookieHelpers.js`, `js-cookie`,
 * `viewport.js`, `abordagemProativa.js`). Nada é reimplementado no verificador:
 * quem lê o cookie, quem desce o degrau e quem grava o cookie de volta são as
 * mesmas linhas que vão para o `sdk.js` do cliente. O verificador só encena o
 * visitante — rolar, esperar, voltar amanhã.
 *
 * ⚠️ ORIGEM `https://` DE MENTIRA, E ELA É O TESTE
 *
 * A página é servida por `page.route` (sem porta, sem servidor, sem disputar as
 * portas do coordenador) numa origem `https://`. Chromium trata isso como
 * contexto seguro de verdade — `isSecureContext === true` —, então o cookie sai
 * com `Secure` e é ARMAZENADO com `Secure`. A bateria inteira roda em cima
 * desse cookie: é por isso que "o cookie tem `secure` em HTTPS" aqui não é uma
 * asserção sobre um espião, é a condição de existência de todo o resto.
 *
 * ⚠️ CONTROLE NEGATIVO EMBUTIDO — VERMELHO ANTES DE VERDE
 *
 * Depois da bateria real, o mesmo arquivo reconstrói o bundle com UMA linha
 * sabotada de cada vez e roda a bateria de novo, exigindo que a asserção
 * correspondente REPROVE. Uma asserção que passa com a guarda quebrada não está
 * medindo a guarda, e as três asserções de ausência deste arquivo ("não mostra
 * nada", "o cookie não mexeu") passariam sozinhas num verificador que nunca
 * montou nada. Rodar a sabotagem é o que separa as duas hipóteses.
 *
 * A sabotagem LEVANTA se o alvo não existir mais no fonte, para que ela não
 * vire um `replace` silencioso que não substitui nada e "passa".
 *
 *   node app/javascript/sdk/specs/browser/approach-degradation.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { build } from 'vite';

// ── infra de asserção ───────────────────────────────────────────────────────
const criarRegistro = () => {
  const itens = [];
  const check = (id, nome, atual, esperado) => {
    itens.push({ id, nome, ok: atual === esperado, atual, esperado });
  };
  return { itens, check };
};

const imprimir = registro => {
  registro.itens.forEach(({ id, nome, ok, atual, esperado }) => {
    console.log(
      `${ok ? '  ok  ' : ' FAIL '} ${id} ${nome}\n        esperado=${esperado}  recebido=${atual}`
    );
  });
};

const idsReprovados = registro =>
  registro.itens.filter(i => !i.ok).map(i => i.id);

// ── o bundle real ───────────────────────────────────────────────────────────
const RAIZ = new URL('../../../../../', import.meta.url).pathname;
const JS = `${RAIZ}app/javascript/`;

const empacotar = async (plugins = []) => {
  const saida = await build({
    root: RAIZ,
    logLevel: 'error',
    configFile: false,
    plugins,
    resolve: {
      alias: {
        shared: `${JS}shared`,
        widget: `${JS}widget`,
        dashboard: `${JS}dashboard`,
        helpers: `${JS}shared/helpers`,
        assets: `${JS}dashboard/assets`,
      },
    },
    build: {
      write: false,
      lib: {
        entry: `${JS}sdk/IFrameHelper.js`,
        formats: ['iife'],
        name: 'wootHost',
        fileName: 'h',
      },
    },
  });
  return saida[0].output[0].code;
};

/**
 * Troca UMA expressão do fonte de UM módulo. Levanta quando o alvo sumiu: uma
 * sabotagem que não sabota é um controle negativo que aprova qualquer coisa.
 */
const sabotagem = (arquivo, de, para) => ({
  name: 'sabotagem',
  transform(code, id) {
    if (!id.endsWith(arquivo)) return null;
    if (!code.includes(de)) {
      throw new Error(
        `sabotagem não aplicada: "${de}" não existe mais em ${arquivo}`
      );
    }
    return code.replace(de, para);
  },
});

const fonteSdk = readFileSync(new URL('../../sdk.js', import.meta.url), 'utf8');
const CSS = fonteSdk.match(/export const SDK_CSS = `([\s\S]*?)\n`;/)[1];

// ── a página do site do cliente ─────────────────────────────────────────────
const HOST = 'approach.test';
const INTRUSO = 'outro.test';

// O `<iframe>` do widget é REAL: `getAppFrame()` o encontra pelo id, a ponte
// `sendMessage` posta nele de verdade, e `isTrustedFrameOrigin` compara a
// origem do `src` dele. O segundo iframe é de OUTRA origem e existe só para o
// controle: ele tenta a mesma mensagem e tem de ser ignorado.
const paginaHost = bundle => `<!doctype html>
<html lang="pt-BR"><head><title>d</title><style>${CSS}</style></head>
<body style="margin:0;height:3000px">
  <div id="cw-bubble-holder" class="woot--bubble-holder">
    <button id="lancador" class="woot-widget-bubble woot-elements--right"></button>
  </div>
  <iframe id="chatwoot_live_chat_widget" src="/frame.html" style="display:none"></iframe>
  <iframe id="intruso" src="https://${INTRUSO}/frame.html" style="display:none"></iframe>
  <script>${bundle}</script>
</body></html>`;

const PAGINA_FRAME = '<!doctype html><html lang="pt-BR"><body>f</body></html>';

const CANAL = {
  avatarUrl: 'https://exemplo.test/a.png',
  teaserText: 'Fale com a gente',
  replyTime: 'Responde em minutos',
};

const MENSAGEM_CONVERSAO = `chatwoot-widget:${JSON.stringify({
  event: 'onEvent',
  eventIdentifier: 'chatwoot:message-sent',
})}`;

// ── o visitante ─────────────────────────────────────────────────────────────
const abrirContexto = async (browser, bundle, esquema) => {
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 800 },
  });
  const page = await ctx.newPage();
  await page.clock.install({ time: new Date() });
  await page.route('**/*', rota => {
    const ehFrame = new URL(rota.request().url()).pathname === '/frame.html';
    return rota.fulfill({
      contentType: 'text/html; charset=utf-8',
      body: ehFrame ? PAGINA_FRAME : paginaHost(bundle),
    });
  });
  return { ctx, page, base: `${esquema}://${HOST}/` };
};

/**
 * Uma VISITA: documento novo, `window` novo, módulo reexecutado — e o cookie
 * atravessando por conta do navegador. Devolve o cartão que o visitante vê, ou
 * `null` quando não há cartão nenhum.
 */
const visitar = async ({ page, base }, gatilhos) => {
  await page.goto(base);
  await page.evaluate(g => {
    window.$chatwoot = { baseDomain: undefined, position: 'right' };
    const { IFrameHelper } = window.wootHost;
    IFrameHelper.initPostMessageCommunication();
    IFrameHelper.montarTeaserSeConfigurado(
      document.getElementById('cw-bubble-holder'),
      { ...window.wootCanal, widgetTriggers: g }
    );
    // As DUAS condições do gatilho composto: rolagem primeiro, relógio depois.
    window.scrollTo(0, 1500);
    window.dispatchEvent(new Event('scroll'));
  }, gatilhos);
  await page.clock.fastForward(9000);
  await page.waitForTimeout(60);
  return page.evaluate(() => {
    const cartao = document.querySelector('.woot-teaser');
    if (!cartao) return null;
    return {
      classe: cartao.className,
      altura: Math.round(cartao.getBoundingClientRect().height),
    };
  });
};

/** O cookie como o NAVEGADOR o guarda — nome, valor, prazo, `secure`. */
const cookieDoJar = async ctx =>
  (await ctx.cookies()).find(c => c.name === 'cw_approach') || null;

/**
 * Posta a mensagem DE DENTRO do iframe indicado, que é o que dá à mensagem a
 * `origin` que `isTrustedFrameOrigin` confere.
 *
 * ⚠️ `contentWindow.postMessage(...)` do lado do host faz o CONTRÁRIO: entrega
 * a mensagem ao iframe. Escrito assim, o handler do host nunca roda — e a
 * asserção de controle ("mensagem de outra origem é ignorada") passa vazia,
 * porque nenhuma mensagem chega de origem nenhuma. Foi assim na primeira
 * execução deste arquivo: C2 verde e C3 vermelho, com o mesmo motivo.
 */
const postarDoIframe = async (page, origem, mensagem) => {
  const frame = page.frames().find(f => f.url().startsWith(origem));
  if (!frame) throw new Error(`iframe de ${origem} não está na página`);
  await frame.evaluate(msg => window.parent.postMessage(msg, '*'), mensagem);
  await page.waitForTimeout(120);
};

/**
 * A bateria inteira, para poder ser reexecutada contra um bundle sabotado.
 * Cada asserção tem um id estável: é por ele que o controle negativo cobra
 * QUAL asserção a sabotagem derrubou.
 */
const rodarBateria = async (browser, bundle, check) => {
  const GATILHOS = { enabled: true, approach: 'bold', degrade_on_return: true };

  // ── A. as três visitas em `bold` (aceites 1–3; 2c, pontas 1 e 2) ──────────
  const a = await abrirContexto(browser, bundle, 'https');
  await a.page.addInitScript(canal => {
    window.wootCanal = canal;
  }, CANAL);

  const v1 = await visitar(a, GATILHOS);
  check(
    'A1',
    'visita 1 (novo) recebe o nível CONFIGURADO',
    String(v1 && v1.classe.includes('woot-teaser--bold')),
    'true'
  );
  const c1 = await cookieDoJar(a.ctx);
  check('A2', 'e o navegador guardou o cookie em "1.0"', c1 && c1.value, '1.0');

  const v2 = await visitar(a, GATILHOS);
  check(
    'A3',
    'visita 2 (voltou sem converter) DESCE um degrau',
    String(v2 && v2.classe.includes('woot-teaser--discreet')),
    'true'
  );
  const c2 = await cookieDoJar(a.ctx);
  check('A4', 'e o cookie foi para "2.0"', c2 && c2.value, '2.0');
  check(
    'A5',
    'e o cartão da visita 2 é MENOR que o da visita 1 (altura medida na cascata)',
    v1 && v2
      ? `${v2.altura}<${v1.altura}=${v2.altura < v1.altura}`
      : 'sem cartão',
    v1 && v2 ? `${v2.altura}<${v1.altura}=true` : 'sem cartão'
  );

  const v3 = await visitar(a, GATILHOS);
  check(
    'A6',
    'visita 3 cai da escada e NÃO mostra cartão nenhum',
    String(v3),
    'null'
  );
  const c3 = await cookieDoJar(a.ctx);
  check(
    'A7',
    'e o cookie NÃO mexeu — não abordou, não gastou degrau',
    c3 && c3.value,
    '2.0'
  );

  // ── B. o topo da escada, na função real de decisão ────────────────────────
  // `nivelDeAbordagem` é a MESMA linha que `montarTeaserSeConfigurado` chama;
  // aqui ela é consultada direto porque o degrau `aggressive` se manifesta
  // abrindo o painel (4.20) e não num cartão que dê para medir.
  const nivelCom = async gatilhos =>
    a.page.evaluate(
      g => window.wootHost.IFrameHelper.nivelDeAbordagem(g).nivel,
      gatilhos
    );
  check(
    'B1',
    'com o cookie em "2.0", `aggressive` já desceu dois degraus (→ discreet)',
    await nivelCom({ approach: 'aggressive' }),
    'discreet'
  );
  await a.ctx.clearCookies();
  check(
    'B2',
    'e visitante NOVO recebe `aggressive` inteiro (2c, ponta 1)',
    await nivelCom({ approach: 'aggressive' }),
    'aggressive'
  );
  await a.ctx.close();

  // ── C. converter zera o contador, pela PONTE REAL (aceite 4; 2c, ponta 3) ─
  const b = await abrirContexto(browser, bundle, 'https');
  await b.page.addInitScript(canal => {
    window.wootCanal = canal;
  }, CANAL);
  await visitar(b, GATILHOS);
  await visitar(b, GATILHOS);
  check(
    'C1',
    'duas visitas antes de converter deixam o cookie em "2.0"',
    (await cookieDoJar(b.ctx)).value,
    '2.0'
  );

  // CONTROLE: a MESMA mensagem, de outra origem. Sem esta asserção, "o cookie
  // zerou" não distingue "a ponte funcionou" de "qualquer janela manda no
  // cookie do visitante".
  await postarDoIframe(b.page, `https://${INTRUSO}/`, MENSAGEM_CONVERSAO);
  check(
    'C2',
    'a mesma mensagem vinda de OUTRA origem é ignorada (o cookie fica em "2.0")',
    (await cookieDoJar(b.ctx)).value,
    '2.0'
  );

  await postarDoIframe(
    b.page,
    `https://${HOST}/frame.html`,
    MENSAGEM_CONVERSAO
  );
  const cConv = await cookieDoJar(b.ctx);
  check(
    'C3',
    'converter pelo iframe do widget zera o contador e marca a conversão ("0.1")',
    cConv && cConv.value,
    '0.1'
  );

  const v4 = await visitar(b, GATILHOS);
  check(
    'C4',
    'e a visita seguinte volta ao nível CONFIGURADO (2c, ponta 3)',
    String(v4 && v4.classe.includes('woot-teaser--bold')),
    'true'
  );

  // O SEGUNDO CAMPO DO COOKIE, MEDIDO — e ele é o ponto em aberto do bloco.
  //
  // `converteu` é ESCRITO (aqui, em C3) e nunca LIDO: `nivelDeAbordagem` só
  // desestrutura o primeiro campo. Quem faz "converter volta ao nível
  // configurado" acontecer é o contador indo a zero, não a marca.
  //
  // `o3-abordagem.md` declara isso de propósito ("já converteu não sobrevive a
  // uma abordagem nova"): o par descreve o CICLO CORRENTE, não a vida do
  // visitante. A consequência é esta asserção — a marca dura de uma conversão
  // até a abordagem seguinte, e some.
  //
  // A asserção existe para que a decisão pare de ser invisível. Se algum dia o
  // produto quiser que quem já conversou não volte a descer a escada, é ELA que
  // reprova primeiro, e a conversa acontece antes da mudança, não depois.
  check(
    'C5',
    'e a marca de conversão NÃO sobrevive à abordagem seguinte (o par é do ciclo, não da vida)',
    (await cookieDoJar(b.ctx)).value,
    '1.0'
  );

  // ── D. o cookie inspecionado no jar (aceite 6 + A15) ──────────────────────
  const cookieHttps = await cookieDoJar(b.ctx);
  check(
    'D1',
    'em HTTPS o navegador guardou o cookie com `secure`',
    String(cookieHttps.secure),
    'true'
  );
  check(
    'D2',
    'e ele é de PRIMEIRA PARTE — domínio do próprio site',
    cookieHttps.domain,
    HOST
  );
  check('D3', 'e `SameSite=Lax`', cookieHttps.sameSite, 'Lax');
  const dias = Math.round((cookieHttps.expires - Date.now() / 1000) / 86400);
  check(
    'D4',
    'e o prazo que o NAVEGADOR gravou é de 30 dias',
    String(dias),
    '30'
  );
  check(
    'D5',
    'e o valor guarda DUAS coisas e nada mais (A15)',
    String(/^\d+\.[01]$/.test(cookieHttps.value)),
    'true'
  );
  await b.ctx.close();

  // ── E. `degrade_on_return: false` (aceite 5; 2c, ponta 4) ─────────────────
  const c = await abrirContexto(browser, bundle, 'https');
  await c.page.addInitScript(canal => {
    window.wootCanal = canal;
  }, CANAL);
  const SEM_QUEDA = {
    enabled: true,
    approach: 'bold',
    degrade_on_return: false,
  };
  const s1 = await visitar(c, SEM_QUEDA);
  const s2 = await visitar(c, SEM_QUEDA);
  const s3 = await visitar(c, SEM_QUEDA);
  const niveis = [s1, s2, s3].map(v =>
    v ? v.classe.match(/woot-teaser--(\w+)/)[1] : 'nenhum'
  );
  check(
    'E1',
    'com `degrade_on_return: false` o nível não cai em três visitas',
    niveis.join(','),
    'bold,bold,bold'
  );
  check(
    'E2',
    'e o contador CONTINUA contando — é ele que mantém o ordinal único do 4.21',
    (await cookieDoJar(c.ctx)).value,
    '3.0'
  );
  await c.ctx.close();

  // ── F. o controle do `secure`: a MESMA gravação em HTTP ───────────────────
  // Sem este par, "tem `secure`" seria compatível com "o helper sempre põe
  // `secure`" — que quebraria todo site em HTTP em silêncio, porque o Chromium
  // descarta o cookie e o widget perde o estado sem um único erro.
  const d = await abrirContexto(browser, bundle, 'http');
  await d.page.addInitScript(canal => {
    window.wootCanal = canal;
  }, CANAL);
  await visitar(d, GATILHOS);
  const cookieHttp = await cookieDoJar(d.ctx);
  check(
    'F1',
    'em HTTP o cookie é gravado (o site em HTTP não pode perder o estado)',
    cookieHttp && cookieHttp.value,
    '1.0'
  );
  check(
    'F2',
    'e SEM `secure`, senão o Chromium o descartaria em silêncio',
    String(cookieHttp && cookieHttp.secure),
    'false'
  );
  await d.ctx.close();
};

// ── execução ────────────────────────────────────────────────────────────────
const browser = await chromium.launch();

const real = criarRegistro();
const BUNDLE = await empacotar();
await rodarBateria(browser, BUNDLE, real.check);
console.log('── a bateria real ─────────────────────────────────────────────');
imprimir(real);

// As sabotagens: uma linha de cada vez, e cada uma tem de derrubar a asserção
// que existe por causa dela. `alvo` é o id que PRECISA reprovar.
const SABOTAGENS = [
  {
    nome: 'S1 — `degradar` ignora o contador',
    alvo: ['A3', 'A6'],
    plugin: sabotagem(
      'sdk/tracking/approach.js',
      'NIVEIS[NIVEIS.indexOf(nivel) + degraus]',
      'NIVEIS[NIVEIS.indexOf(nivel)]'
    ),
  },
  {
    nome: 'S2 — converter não zera o contador',
    alvo: ['C3', 'C4'],
    plugin: sabotagem(
      'sdk/IFrameHelper.js',
      'gravarAbordagem(0, true, window.$chatwoot.baseDomain);',
      ';'
    ),
  },
  {
    nome: 'S3 — `degrade_on_return: false` deixa de ser respeitado',
    alvo: ['E1'],
    plugin: sabotagem(
      'sdk/IFrameHelper.js',
      'gatilhos.degrade_on_return === false',
      'false'
    ),
  },
  {
    nome: 'S4 — o cookie perde o `secure` em HTTPS',
    alvo: ['D1'],
    plugin: sabotagem(
      'sdk/cookieHelpers.js',
      "secure: window.location.protocol === 'https:'",
      'secure: false'
    ),
  },
  {
    nome: 'S5 — o prazo do cookie deixa de ser 30 dias',
    alvo: ['D4'],
    plugin: sabotagem(
      'sdk/tracking/approach.js',
      'const DIAS = 30;',
      'const DIAS = 31;'
    ),
  },
];

const controles = criarRegistro();
// Em série, e não `Promise.all`: as baterias disputam o mesmo navegador e o
// mesmo jar de cookies. Em paralelo elas se misturariam e o resultado seria
// função da ordem de agendamento.
await SABOTAGENS.reduce(async (anterior, { nome, alvo, plugin }) => {
  await anterior;
  const bundleQuebrado = await empacotar([plugin]);
  const registro = criarRegistro();
  await rodarBateria(browser, bundleQuebrado, registro.check);
  const caiu = idsReprovados(registro);
  controles.check(
    nome,
    `derruba ${alvo.join('+')} (reprovou: ${caiu.join(',') || 'nada'})`,
    alvo.every(id => caiu.includes(id)) ? 'derrubou' : 'não derrubou',
    'derrubou'
  );
}, Promise.resolve());

console.log(
  '\n── os controles negativos (vermelho antes de verde) ───────────'
);
imprimir(controles);

await browser.close();

const total = real.itens.length + controles.itens.length;
const falhas = [...real.itens, ...controles.itens].filter(i => !i.ok);
console.log(`\n${total - falhas.length}/${total} asserções ok`);
process.exit(falhas.length ? 1 : 0);
