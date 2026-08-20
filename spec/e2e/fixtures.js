const { test: base, expect } = require('@playwright/test');

/**
 * O FIXTURE ANTI-ERRO — bloco 0.11 (D14, QUALITY-KIT §1.5).
 *
 * ── POR QUE ELE EXISTE, COM O CASO DESTA BASE ───────────────────────────────────────────
 *
 * Um E2E verde sem ele diz apenas *"a página não travou"*. O precedente é desta base: um
 * `NoMethodError` que devolvia **HTTP 500 em toda requisição de IP real** atravessou 4.619
 * testes verdes, os 16 snapshots, a suíte Ruby, o build e uma validação de navegador inteira.
 * O erro estava no console o tempo todo. Ninguém media o console.
 *
 * Os 20 snapshots do widget têm o mesmo ponto cego por construção: eles comparam pixels. Um
 * widget que monta a tela certa cuspindo `TypeError` passa em todos os 20.
 *
 * ── AS QUATRO CATEGORIAS, E POR QUE NÃO SÃO UM NÚMERO SÓ ────────────────────────────────
 *
 * Juntá-las esconde qual está acontecendo, e cada uma tem um dono diferente:
 *
 *   · `pageerror`     exceção NÃO CAPTURADA que subiu ao `window.onerror`. É o mais grave:
 *                     alguma coisa parou de executar no meio.
 *   · `console`       `console.error` — um LOG. O código seguiu; alguém escolheu reclamar.
 *   · `http`          resposta com status >= 400. Pode ser nossa (500) ou de contrato (404).
 *   · `rede`          `requestfailed` — a requisição não chegou a ter resposta (DNS, recusa,
 *                     bloqueio). NÃO é HTTP: não há status. Um teste que derruba um servidor
 *                     de propósito produz isto, não aquilo.
 *
 * ── O QUE É AMBIENTE E O QUE É PRODUTO (o critério, escrito) ────────────────────────────
 *
 * Um fixture que pega erro de ambiente vira ruído, e ruído faz alguém desligá-lo — que é a
 * única forma de este bloco virar praga. O critério para uma entrada ser AMBIENTE:
 *
 *   1. o erro vem de dependência EXTERNA que este ambiente de validação não provisiona
 *      (WAHA, gateway de e-mail, storage de terceiro); **e**
 *   2. a ausência dela não é defeito do código sob teste — o mesmo cenário passa onde o
 *      serviço existe; **e**
 *   3. o padrão nomeia a URL/mensagem específica, nunca uma família inteira.
 *
 * Falhou qualquer um dos três? É **produto**, e produto BLOQUEIA. 404 de asset nosso, 500
 * nosso, `console.error` de código nosso — tudo produto, mesmo que "sempre esteve ali".
 *
 * ── OS DOIS ESCAPES, E POR QUE SÃO DIFERENTES ───────────────────────────────────────────
 *
 *   · `IGNORAR` (global, aqui embaixo) — só AMBIENTE, pelos três critérios acima. Não é
 *     exigido que ocorra: o serviço pode existir na máquina de alguém.
 *   · `errosEsperados` (por cenário) — o teste que exercita o caminho de FALHA declara o que
 *     ele mesmo provoca: `test.use({ errosEsperados: [/mensagem/] })`. E aqui a regra é mais
 *     dura: **erro declarado que NÃO aconteceu reprova**. Escape que sobrevive ao cenário que
 *     o justificava é exatamente como uma lista destas vira decoração.
 *
 * Nenhum dos dois aceita catch-all — ver `recusarPadraoAmplo`.
 */

/**
 * AMBIENTE, e nada mais. Cada entrada carrega a razão na linha, porque a regra MUST NOT do
 * §10.3 é "não silenciar erro de console sem justificar em comentário".
 *
 * Está vazia de propósito. A lista da linha de base medida em 19/08/2026 está no relatório
 * `plano/redesenho/execucao/o0-fixture.md`; nada foi movido para cá sem passar pelos três
 * critérios acima. Um exemplo do formato, para quando a primeira entrada for necessária:
 *
 *   {
 *     categoria: 'http',
 *     padrao: /\/api\/v1\/accounts\/\d+\/waha_connections\b.*\b503\b/,
 *     razao:
 *       'WAHA não é provisionado no ambiente de validação. Medido: 503 em toda chamada, e ' +
 *       'o mesmo cenário passa onde a instância existe. Não é defeito do widget.',
 *   },
 */
const IGNORAR = [];

/** Um padrão que casaria com quase tudo não é escape: é o fixture desligado. */
const recusarPadraoAmplo = (padrao, onde) => {
  const fonte = padrao instanceof RegExp ? padrao.source : String(padrao);
  const amplo = ['', '.*', '.+', '^.*$', '[\\s\\S]*'].includes(fonte);
  if (amplo || fonte.length < 4) {
    throw new Error(
      `${onde}: o padrão ${fonte || '(vazio)'} é amplo demais para ser um escape. ` +
        'Nomeie a mensagem ou a URL — um catch-all desliga o fixture sem que ninguém veja.'
    );
  }
};

const casa = (padrao, texto) =>
  padrao instanceof RegExp
    ? padrao.test(texto)
    : texto.includes(String(padrao));

const CATEGORIAS = ['pageerror', 'console', 'http', 'rede'];

/**
 * `report` levanta a LINHA DE BASE sem quebrar a suíte: conta e imprime, não reprova. Existe
 * para o primeiro inventário do que já está sujo, e para mais nada — o padrão é bloquear, e
 * quem rodar sem a variável tem o comportamento do aceite.
 */
const SOMENTE_RELATAR = process.env.E2E_ANTIERRO === 'report';

// Um gate desligado em silêncio é pior que gate nenhum: a suíte fica verde e ninguém sabe por
// quê. Se a variável vazar para um CI ou para o `.env` de alguém, este aviso aparece uma vez
// por processo, alto, e quem estiver lendo o log entende que o resultado não vale como aceite.
let avisouDoModo = false;
const avisarQueOGateEstaDesligado = () => {
  if (avisouDoModo) return;
  avisouDoModo = true;
  // eslint-disable-next-line no-console
  console.warn(
    '\n  ┌──────────────────────────────────────────────────────────────────────────┐\n' +
      '  │  E2E_ANTIERRO=report — O FIXTURE ANTI-ERRO NÃO ESTÁ REPROVANDO.          │\n' +
      '  │  Este modo existe para levantar linha de base (bloco 0.11). Um resultado │\n' +
      '  │  verde aqui NÃO vale como aceite. Rode sem a variável para o gate valer. │\n' +
      '  └──────────────────────────────────────────────────────────────────────────┘\n'
  );
};

/**
 * A ARMADILHA DA TUPLA DO PLAYWRIGHT — medida nesta base em 19/08/2026, e a razão de o escape
 * ser um OBJETO e não um array cru.
 *
 * `test.use({ opcao: [a, b] })` é ambíguo para o Playwright: ele também aceita a sintaxe
 * `[valor, { option: true }]`. A heurística dele é "array de 2 posições cujo segundo item é
 * objeto" — e `RegExp` **é** objeto. Resultado medido, com um spec de uma linha:
 *
 *     test.use({ opt: [/aaa/, /bbb/] })   ->   opt === /aaa/     (não é array; /bbb/ sumiu)
 *
 * Ou seja: o escape funcionaria com **1** padrão, funcionaria com **3 ou mais**, e quebraria
 * com **exatamente 2** — descartando o segundo em silêncio. Um escape que perde padrão sem
 * avisar é a forma mais cara de este fixture virar praga: o teste fica vermelho por um erro
 * que o autor achou que tinha declarado.
 *
 * Por isso a forma canônica é `{ padroes: [...] }`, que nunca é confundida com tupla. As duas
 * outras formas são toleradas para quem escrever o intuitivo, e o caso quebrado é detectado e
 * NOMEADO em vez de silencioso — ver `normalizarEscape`.
 */
const normalizarEscape = (valor, titulo) => {
  if (valor && !Array.isArray(valor) && Array.isArray(valor.padroes))
    return valor.padroes;
  if (Array.isArray(valor)) return valor;

  throw new Error(
    `errosEsperados em "${titulo}" chegou como ${Object.prototype.toString.call(valor)} ` +
      'em vez de lista.\n' +
      'Você provavelmente escreveu `test.use({ errosEsperados: [/a/, /b/] })` com DOIS ' +
      'padrões: o Playwright leu isso como a tupla `[valor, options]` e descartou o segundo.\n' +
      'Use a forma canônica: `test.use({ errosEsperados: { padroes: [/a/, /b/] } })`.'
  );
};

const test = base.extend({
  // Declarado por cenário: `test.use({ errosEsperados: { padroes: [/…/] } })`.
  errosEsperados: [{ padroes: [] }, { option: true }],

  page: async ({ page, errosEsperados: escapeBruto }, use, testInfo) => {
    const errosEsperados = normalizarEscape(escapeBruto, testInfo.title);
    errosEsperados.forEach((p, i) =>
      recusarPadraoAmplo(p, `errosEsperados[${i}] em "${testInfo.title}"`)
    );
    IGNORAR.forEach((e, i) => recusarPadraoAmplo(e.padrao, `IGNORAR[${i}]`));

    const achados = [];
    const registrar = (categoria, texto) => achados.push({ categoria, texto });

    const observar = alvo => {
      alvo.on('pageerror', erro =>
        registrar(
          'pageerror',
          `${erro.message}${erro.stack ? `\n      ${erro.stack.split('\n')[1]?.trim() ?? ''}` : ''}`
        )
      );
      alvo.on('console', msg => {
        if (msg.type() === 'error') {
          const l = msg.location();
          registrar(
            'console',
            `${msg.text()}${l?.url ? `  (${l.url}:${l.lineNumber})` : ''}`
          );
        }
      });
      alvo.on('requestfailed', req =>
        registrar(
          'rede',
          `${req.method()} ${req.url()} — ${req.failure()?.errorText || 'motivo desconhecido'}`
        )
      );
      alvo.on('response', res => {
        if (res.status() >= 400) {
          registrar(
            'http',
            `${res.status()} ${res.request().method()} ${res.url()}`
          );
        }
      });
    };

    observar(page);
    // O widget abre popout (`popoutChatWindow`). Erro que acontece na janela nova é erro
    // igual, e sem isto ele não é observado por ninguém.
    page.context().on('page', observar);

    await use(page);

    const usados = new Set();
    const sobraram = achados.filter(({ categoria, texto }) => {
      const linha = `${categoria}: ${texto}`;
      const esperado = errosEsperados.findIndex(
        p => casa(p, texto) || casa(p, linha)
      );
      if (esperado !== -1) {
        usados.add(esperado);
        return false;
      }
      return !IGNORAR.some(
        e => e.categoria === categoria && casa(e.padrao, texto)
      );
    });

    if (SOMENTE_RELATAR) {
      avisarQueOGateEstaDesligado();
      if (achados.length) {
        const porCategoria = CATEGORIAS.map(
          c => `${c}=${achados.filter(a => a.categoria === c).length}`
        ).join(' ');
        // eslint-disable-next-line no-console
        console.log(
          `\n[E2E_ANTIERRO] ${testInfo.titlePath.join(' > ')}\n  ${porCategoria}\n` +
            achados.map(a => `  · ${a.categoria}: ${a.texto}`).join('\n')
        );
      }
      return;
    }

    const naoOcorreram = errosEsperados
      .map((p, i) => (usados.has(i) ? null : p))
      .filter(Boolean);

    expect(
      naoOcorreram.map(String),
      'errosEsperados que NÃO aconteceram — o cenário mudou e o escape ficou para trás'
    ).toEqual([]);

    const resumo = CATEGORIAS.filter(c => sobraram.some(s => s.categoria === c))
      .map(c => `${sobraram.filter(s => s.categoria === c).length} ${c}`)
      .join(', ');

    expect(
      sobraram.map(({ categoria, texto }) => `${categoria}: ${texto}`),
      sobraram.length
        ? `A página produziu ${resumo}. Nenhum é esperado por este cenário nem é ambiente ` +
            '(ver o critério no topo de spec/e2e/fixtures.js).'
        : 'sem erros'
    ).toEqual([]);
  },
});

module.exports = {
  test,
  expect,
  IGNORAR,
  recusarPadraoAmplo,
  normalizarEscape,
  CATEGORIAS,
};
