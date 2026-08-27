/**
 * Mecanismo de aceite do bloco 2.13, em NAVEGADOR.
 *
 * ACEITE (§2.2): «Erro forçado aparece no GlitchTip com PII removida; nada vaza
 * para o `window.onerror` do site do cliente».
 *
 * Este arquivo cobre a metade que **só** existe em navegador: a fronteira entre
 * o documento do site do cliente e o documento do widget. Em jsdom não há
 * iframe de verdade, não há propagação de erro entre documentos e não há
 * `unhandledrejection` real — um teste ali provaria apenas que o dublê funciona.
 *
 * O módulo sob teste é o `widget/helpers/telemetry.js` DE VERDADE, empacotado
 * pelo esbuild em tempo de execução (ver o harness). Sem cópia e sem artefato
 * commitado: se o módulo mudar, este teste roda o novo.
 *
 * "Aparece no GlitchTip" é medido contra um receptor local que fala o mesmo
 * protocolo do endpoint. Disparar evento de teste contra o GlitchTip de
 * produção — que recebe a frota inteira — polui a triagem real de outras
 * pessoas, e está registrado no relatório como o passo que depende de
 * autorização.
 */
// Bloco 0.11 — fixture anti-erro. Import DAQUI, nunca de `@playwright/test`.
const { test, expect } = require('../fixtures');
const { iniciarServidor } = require('./harness/hostServer');

let servidor;

test.beforeAll(async () => {
  servidor = await iniciarServidor();
});

test.afterAll(async () => {
  await servidor?.fechar();
});

test.beforeEach(async () => {
  servidor.limparRecebidos();
});

const abrir = async page => {
  await page.goto(servidor.origem, { waitUntil: 'domcontentloaded' });
  const widget = page.frameLocator('#widget');
  await expect(widget.locator('#app')).toHaveText('painel');
  return widget;
};

// Dispara um erro DENTRO do iframe, pelo caminho real: um `catch` que chama o
// reporter, como os 14 sítios instrumentados do widget fazem.
const forcarErroNoWidget = (page, mensagem, origem = 'teste') =>
  page.frame({ url: /\/widget$/ }).evaluate(
    ([texto, ondeVeio]) => {
      try {
        throw new Error(texto);
      } catch (erro) {
        return window.Telemetria.reportWidgetError(erro, { origem: ondeVeio });
      }
    },
    [mensagem, origem]
  );

test.describe('2.13 — o relatório sai, e sai raspado', () => {
  test('um erro forçado vira um envelope no endpoint', async ({ page }) => {
    await abrir(page);
    await forcarErroNoWidget(
      page,
      'falha ao carregar contato',
      'store/contacts'
    );

    await expect
      .poll(() => servidor.recebidos.length, { timeout: 5000 })
      .toBe(1);

    const envelope = servidor.recebidos[0];
    expect(envelope.name).toBe('Error');
    expect(envelope.message).toBe('falha ao carregar contato');
    expect(envelope.context.origem).toBe('store/contacts');
    expect(envelope.website_token).toBe('token-e2e-2-13');
    expect(envelope.release).toBe('v-teste');
    expect(envelope.stack).toContain('Error');
  });

  test('a PII é removida ANTES de sair do navegador', async ({ page }) => {
    // Não basta o servidor raspar: se a PII sai na rede, ela já atravessou a
    // máquina do visitante e qualquer proxy no caminho. Aqui medimos o corpo
    // que o navegador emitiu.
    await abrir(page);
    await forcarErroNoWidget(
      page,
      'falha ao enviar para maria.silva@empresa.com.br, tel +55 11 98765-4321, cpf 123.456.789-09',
      'store/contacts'
    );

    await expect
      .poll(() => servidor.recebidos.length, { timeout: 5000 })
      .toBe(1);

    const bruto = JSON.stringify(servidor.recebidos[0]);
    expect(bruto).not.toContain('maria.silva@empresa.com.br');
    expect(bruto).not.toContain('98765-4321');
    expect(bruto).not.toContain('123.456.789-09');
    expect(servidor.recebidos[0].message).toContain('[email]');
    expect(servidor.recebidos[0].message).toContain('[telefone]');
    expect(servidor.recebidos[0].message).toContain('[documento]');
  });

  test('o envelope não tem por onde carregar a conversa', async ({ page }) => {
    await abrir(page);
    await page.frame({ url: /\/widget$/ }).evaluate(() => {
      const erro = new Error('erro qualquer');
      return window.Telemetria.reportWidgetError(erro, {
        origem: 'chat',
        content: 'oi, meu cartão é 4111 1111 1111 1111',
      });
    });

    await expect
      .poll(() => servidor.recebidos.length, { timeout: 5000 })
      .toBe(1);

    const envelope = servidor.recebidos[0];
    expect(Object.keys(envelope).sort()).toEqual(
      [
        'context',
        'message',
        'name',
        'release',
        'stack',
        'url',
        'website_token',
      ].sort()
    );
    expect(JSON.stringify(envelope)).not.toContain('4111');
  });
});

test.describe('2.13 — nada vaza para o site do cliente', () => {
  // ESTES DOIS TESTES NÃO DECLARAM ESCAPE NENHUM, E ISSO É O ACEITE.
  //
  // Eles já declararam — e por isso reprovavam. O escape morava no describe INTEIRO, com dois
  // padrões que só UM dos três cenários provoca; o fixture do bloco 0.11 reprova escape
  // declarado que não acontece, e reprovava aqui, com o teste em si passando (`vazamentos`
  // medido `[]`, `pageerror=0`). O escape estava no lugar errado.
  //
  // Ao mover o escape para o cenário que o justifica, sobrou um erro de verdade nos outros
  // dois: um `net::ERR_ABORTED` no NOSSO `POST` de telemetria, 40 ms DEPOIS do 204 e com a
  // página ainda viva — o Chromium cancelando o corpo de resposta que o reporter nunca lia.
  // Dez deles no cenário do teto. Isso é a nossa telemetria pintada de vermelho no devtools
  // do site do cliente, e a correção foi no PRODUTO (`telemetry.js` drena a resposta), não
  // aqui. Sem aquela linha, estes dois testes ficam vermelhos de novo — é o que os torna
  // acusadores em vez de decorativos.

  test('o erro registrado não aparece no `window.onerror` do pai', async ({
    page,
  }) => {
    await abrir(page);
    await forcarErroNoWidget(page, 'erro que deve ficar contido');
    await expect
      .poll(() => servidor.recebidos.length, { timeout: 5000 })
      .toBe(1);

    const vazamentos = await page.evaluate(() => window.vazamentos);
    expect(vazamentos).toEqual([]);
  });

  // Bloco 0.11 — ESCAPE POR CENÁRIO, e o cenário é ESTE, sozinho num describe próprio.
  //
  // Aqui o endpoint de telemetria é derrubado de propósito: é o caminho de falha que este
  // teste existe para exercitar. O `POST` que não completa é o cenário, não defeito — e o que
  // se prova é justamente que ele NÃO vira erro visível no site do cliente.
  //
  // Por que num describe só dele: `test.use` não vale para um teste isolado, e pendurar o
  // escape no describe de cima o daria também aos dois vizinhos, que não derrubam nada. Foi
  // exatamente esse erro de escopo que deixou os dois reprovando.
  //
  // Por que aqui e não em `IGNORAR`: a lista global é só para AMBIENTE (dependência externa
  // não provisionada). Isto é produto, é deliberado, e é deste cenário. Pôr na lista global
  // cegaria o fixture para uma falha real de telemetria em qualquer outro cenário.
  test.describe('com o endpoint derrubado de propósito', () => {
    test.use({
      errosEsperados: {
        padroes: [
          /\/api\/v1\/widget\/telemetry — net::ERR_FAILED/,
          /Failed to load resource: net::ERR_FAILED/,
        ],
      },
    });

    test('o endpoint fora do ar não gera `unhandledrejection` no pai', async ({
      page,
    }) => {
      // O caso que mais assusta: o reporter roda dentro de `catch`. Se a rejeição
      // dele escapasse, um erro REGISTRADO viraria um erro NÃO TRATADO — o
      // oposto do bloco, e no documento de outra empresa.
      await abrir(page);
      await page.route('**/api/v1/widget/telemetry', rota =>
        rota.abort('failed')
      );

      await forcarErroNoWidget(page, 'erro com endpoint fora do ar');
      await page.waitForTimeout(1000);

      const vazamentos = await page.evaluate(() => window.vazamentos);
      expect(vazamentos).toEqual([]);
      expect(servidor.recebidos).toHaveLength(0);
    });
  });

  test('o teto por sessão impede o widget de virar amplificador', async ({
    page,
  }) => {
    // Um erro dentro de um laço de render viraria milhares de POSTs saindo do
    // site do cliente — o widget passaria a ser o problema de desempenho dele.
    await abrir(page);
    await page.frame({ url: /\/widget$/ }).evaluate(async () => {
      for (let i = 0; i < 40; i += 1) {
        try {
          throw new Error(`erro numero ${i}`);
        } catch (erro) {
          // eslint-disable-next-line no-await-in-loop
          await window.Telemetria.reportWidgetError(erro, { origem: 'laco' });
        }
      }
    });

    await page.waitForTimeout(500);
    expect(servidor.recebidos.length).toBeLessThanOrEqual(10);
    expect(servidor.recebidos.length).toBeGreaterThan(0);

    const vazamentos = await page.evaluate(() => window.vazamentos);
    expect(vazamentos).toEqual([]);
  });
});
