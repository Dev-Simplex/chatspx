const { test, expect } = require('@playwright/test');
const fs = require('node:fs');
const {
  iniciarServidor,
  TAG_DO_SNIPPET,
  CAMINHO_DO_SNIPPET,
  CAMINHO_DO_SDK,
} = require('./harness/hostServer');

/**
 * Bloco 5.18 — «configuração viaja por qualquer via; identidade e credencial, só pela API JS».
 *
 * ESTE ARQUIVO É O ACEITE, e ele roda em Chromium de propósito. O módulo de regras
 * (`app/javascript/sdk/snippetConfig.js`) já tinha 32 exemplos verdes antes deste bloco — e o
 * produto, medido em navegador, não recebia UM atributo sequer: a leitura acontecia dentro de
 * `g.onload`, onde `document.currentScript` é `null` por especificação, e a tag do snippet não
 * tinha nenhum dos dois marcadores que o bundle procurava. Um teste em jsdom que montasse a tag
 * e chamasse `run()` de forma síncrona teria passado o tempo inteiro, sobre um produto morto.
 *
 * Snippet real (o mesmo `fixtures/snippet.html` que o spec do modelo prova ser byte a byte o que
 * o servidor entrega) + `sdk.js` real + navegador real.
 */
test.describe('5.18 — data-* de configuração no snippet, em navegador real', () => {
  let servidor;

  test.beforeAll(async () => {
    servidor = await iniciarServidor();
  });

  test.afterAll(async () => {
    await servidor?.fechar();
  });

  const abrir = async (
    page,
    { dataset = {}, settings = null, remover = false } = {}
  ) => {
    const busca = new URLSearchParams();
    if (Object.keys(dataset).length) {
      busca.set('dataset', JSON.stringify(dataset));
    }
    if (settings) busca.set('settings', JSON.stringify(settings));
    if (remover) busca.set('remover', '1');

    const avisos = [];
    page.on('console', mensagem => {
      if (mensagem.type() === 'warning') avisos.push(mensagem.text());
    });

    await page.goto(`${servidor.origem}/?${busca.toString()}`);
    await page.waitForFunction(() => Boolean(window.$chatwoot), null, {
      timeout: 15000,
    });

    return { avisos };
  };

  test('o harness realmente pendura os atributos na tag do snippet', async () => {
    // Guarda contra o falso verde do próprio harness: se o marcador mudar de nome no servidor e
    // não aqui, a injeção vira no-op e todos os exemplos abaixo passariam medindo uma página sem
    // atributo nenhum — que é precisamente o estado que este bloco veio consertar.
    expect(fs.readFileSync(CAMINHO_DO_SNIPPET, 'utf-8')).toContain(
      TAG_DO_SNIPPET
    );
    expect(fs.existsSync(CAMINHO_DO_SDK)).toBe(true);
  });

  test('configuração viaja: o widget nasce com o que o data-* mandou', async ({
    page,
  }) => {
    await abrir(page, {
      dataset: {
        position: 'left',
        launcherTitle: 'Fale com a loja',
        widgetStyle: 'flat',
        locale: 'pt_BR',
      },
    });

    const lido = await page.evaluate(() => ({
      position: window.$chatwoot.position,
      launcherTitle: window.$chatwoot.launcherTitle,
      widgetStyle: window.$chatwoot.widgetStyle,
      locale: window.$chatwoot.locale,
    }));

    expect(lido).toEqual({
      position: 'left',
      launcherTitle: 'Fale com a loja',
      widgetStyle: 'flat',
      locale: 'pt_BR',
    });
  });

  test('data-hide-message-bubble="false" desliga de verdade, não vira a string "false"', async ({
    page,
  }) => {
    // Sem a coerção, TODA flag booleana do snippet seria verdadeira — inclusive a que o
    // integrador escreve justamente para desligar. É o defeito mais silencioso desta via.
    await abrir(page, { dataset: { hideMessageBubble: 'false' } });
    expect(await page.evaluate(() => window.$chatwoot.hideMessageBubble)).toBe(
      false
    );

    await abrir(page, { dataset: { hideMessageBubble: 'true' } });
    expect(await page.evaluate(() => window.$chatwoot.hideMessageBubble)).toBe(
      true
    );
  });

  test('ASSERÇÃO NEGATIVA — identidade e credencial NÃO entram, e a recusa é dita em voz alta', async ({
    page,
  }) => {
    const { avisos } = await abrir(page, {
      dataset: {
        position: 'left',
        email: 'cliente@exemplo.com',
        identifierHash: 'assinatura-que-vale-para-sempre',
        apiKey: 'chave-secreta',
      },
    });

    const estado = await page.evaluate(() => ({
      chaves: Object.keys(window.$chatwoot),
      serializado: JSON.stringify(window.$chatwoot),
      position: window.$chatwoot.position,
    }));

    // a configuração da MESMA tag passou — é o que prova que a recusa é por chave e não uma
    // desistência de ler o dataset inteiro
    expect(estado.position).toBe('left');

    expect(estado.chaves).not.toContain('email');
    expect(estado.chaves).not.toContain('identifierHash');
    expect(estado.chaves).not.toContain('apiKey');
    expect(estado.serializado).not.toContain('cliente@exemplo.com');
    expect(estado.serializado).not.toContain('assinatura-que-vale-para-sempre');
    expect(estado.serializado).not.toContain('chave-secreta');

    // recusa silenciosa faria o integrador achar que configurou e seguir em frente
    const recusa = avisos.find(texto => texto.includes('data-*'));
    expect(recusa).toBeTruthy();
    expect(recusa).toContain('email');
    expect(recusa).toContain('identifierHash');
    expect(recusa).toContain('apiKey');
    expect(recusa).toContain('setUser');
  });

  test('precedência declarada: chatwootSettings vence o data-*', async ({
    page,
  }) => {
    await abrir(page, {
      dataset: { position: 'left', launcherTitle: 'do snippet' },
      settings: { position: 'right' },
    });

    const lido = await page.evaluate(() => ({
      position: window.$chatwoot.position,
      launcherTitle: window.$chatwoot.launcherTitle,
    }));

    // a chave que o site declarou vence; a que ele não declarou continua vindo do snippet
    expect(lido).toEqual({ position: 'right', launcherTitle: 'do snippet' });
  });

  test('a leitura sobrevive à tag sumir do DOM antes do onload', async ({
    page,
  }) => {
    // É o que "ler FORA do onload" compra. Gerenciador de tag que injeta o snippet e limpa o nó,
    // ou CMS que reescreve o `<body>`, deixariam o bundle procurando uma tag que não existe mais.
    // Com a leitura no instante da execução da tag, o valor já foi copiado.
    await abrir(page, { dataset: { position: 'left' }, remover: true });

    expect(
      await page.evaluate(() =>
        Boolean(document.querySelector('script[data-chatspx-snippet]'))
      )
    ).toBe(false);
    expect(await page.evaluate(() => window.$chatwoot.position)).toBe('left');
  });

  test('sem sdk.js, o link alternativo do 2.14 também obedece o data-position', async ({
    page,
  }) => {
    // O link nasce QUANDO o bundle não carrega — ele nunca verá nada que o `sdk.js` resolva. Se a
    // posição só existisse do lado de lá, `data-position="left"` daria widget à esquerda e link
    // alternativo à direita.
    await page.route('**/packs/js/sdk.js', rota => rota.abort());

    await page.goto(
      `${servidor.origem}/?dataset=${encodeURIComponent(
        JSON.stringify({ position: 'left' })
      )}`
    );

    const link = page.locator('#cw-fallback-link');
    await expect(link).toBeVisible({ timeout: 20000 });

    const estilo = await link.getAttribute('style');
    expect(estilo).toContain('left:20px');
    expect(estilo).not.toContain('right:20px');
  });
});
