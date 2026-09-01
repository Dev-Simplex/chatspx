import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Bloco 5.18 — a JUNÇÃO entre o snippet e o bundle.
 *
 * `snippetConfig.spec.js` já cobre a REGRA (o que pode viajar, o que é recusado, a precedência),
 * com 32 exemplos, e cobria antes deste bloco existir — enquanto o produto, medido em Chromium,
 * não recebia um atributo sequer. O que faltava era o cano: quem lê, quando lê e por onde o
 * valor chega ao `runSDK`. É isso que este arquivo trava.
 *
 * O aceite em navegador de verdade mora em `spec/e2e/snippet-data/` — lá o snippet é o que o
 * servidor gera e o `sdk.js` é o que o visitante baixa. Aqui é a guarda rápida, a que roda no CI
 * a cada commit.
 */
describe('5.18 — o dataset do snippet chega ao runSDK', () => {
  let avisos;

  const subirSdk = async () => {
    vi.resetModules();
    const { IFrameHelper } = await import('../IFrameHelper');
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation(() => {});
    await import('../../entrypoints/sdk.js');
  };

  beforeEach(async () => {
    document.body.innerHTML = '';
    document.head.innerHTML = '';
    delete window.$chatwoot;
    delete window.chatwootSettings;
    avisos = [];

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    vi.spyOn(console, 'warn').mockImplementation(mensagem =>
      avisos.push(mensagem)
    );

    await subirSdk();
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const rodar = argumentos =>
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
      ...argumentos,
    });

  it('configuração viaja: o que o snippet leu vira estado do widget', () => {
    rodar({
      snippetDataset: {
        position: 'left',
        launcherTitle: 'Fale com a loja',
        hideMessageBubble: 'false',
        showPopoutButton: 'true',
      },
    });

    expect({
      position: window.$chatwoot.position,
      launcherTitle: window.$chatwoot.launcherTitle,
      hideMessageBubble: window.$chatwoot.hideMessageBubble,
      showPopoutButton: window.$chatwoot.showPopoutButton,
    }).toEqual({
      position: 'left',
      launcherTitle: 'Fale com a loja',
      hideMessageBubble: false,
      showPopoutButton: true,
    });
  });

  it('precedência: `chatwootSettings` vence o `data-*`, chave a chave', () => {
    window.chatwootSettings = { position: 'right' };

    rodar({
      snippetDataset: { position: 'left', launcherTitle: 'do snippet' },
    });

    expect({
      position: window.$chatwoot.position,
      launcherTitle: window.$chatwoot.launcherTitle,
    }).toEqual({ position: 'right', launcherTitle: 'do snippet' });
  });

  it('ASSERÇÃO NEGATIVA — identidade e credencial não entram, e a recusa é dita em voz alta', () => {
    rodar({
      snippetDataset: {
        position: 'left',
        email: 'cliente@exemplo.com',
        identifierHash: 'assinatura-eterna',
        apiKey: 'chave-secreta',
      },
    });

    // a configuração da MESMA tag passou: a recusa é por chave, não desistência de ler o dataset
    expect(window.$chatwoot.position).toBe('left');

    const serializado = JSON.stringify(window.$chatwoot);
    expect(serializado).not.toContain('cliente@exemplo.com');
    expect(serializado).not.toContain('assinatura-eterna');
    expect(serializado).not.toContain('chave-secreta');

    expect(avisos).toHaveLength(1);
    expect(avisos[0]).toContain('email');
    expect(avisos[0]).toContain('identifierHash');
    expect(avisos[0]).toContain('apiKey');
    // e o aviso NÃO repete o valor: ele iria para o console do visitante, que é público
    expect(avisos[0]).not.toContain('cliente@exemplo.com');
  });

  it('reserva do DOM: tag marcada e lida mesmo sem `snippetDataset`', () => {
    // É o caminho de quem monta a tag à mão, e o único que sobrou depois de `document.currentScript`
    // e `#chatwoot-sdk` saírem.
    const tag = document.createElement('script');
    tag.setAttribute('data-chatspx-snippet', '');
    tag.setAttribute('data-position', 'left');
    document.body.appendChild(tag);

    rodar({});

    expect(window.$chatwoot.position).toBe('left');
  });

  it('FORÇA A CONDIÇÃO RUIM — sem dataset e sem marcador, nada viaja e nada é recusado', () => {
    // Este é o mundo de antes do bloco, reproduzido: `runSDK` rodando como callback de
    // `g.onload`, `document.currentScript` nulo e nenhuma tag marcada no documento. A asserção
    // negativa acima passaria também aqui — por ausência de sujeito. Este exemplo é o que
    // distingue "recusou" de "não havia nada para recusar".
    const tag = document.createElement('script');
    tag.setAttribute('data-position', 'left');
    tag.setAttribute('data-email', 'cliente@exemplo.com');
    document.body.appendChild(tag);

    expect(document.currentScript).toBe(null);

    rodar({});

    expect(window.$chatwoot.position).toBe('right');
    expect(avisos).toHaveLength(0);
  });

  it('o dataset do snippet não vira via de identidade nem por acidente de nome', async () => {
    // `data-user-id`, `data-contact-id`, `data-signed-up-at`: variações que um integrador tenta
    // quando a documentação não diz. Todas recusadas, e nenhuma delas cria chave no `$chatwoot`.
    const tentativas = {
      userId: '42',
      contactId: '42',
      signedUpAt: '2026-01-01',
      identifier: 'joao',
      authToken: 'jwt',
    };

    rodar({ snippetDataset: tentativas });

    Object.keys(tentativas).forEach(chave =>
      expect({ chave, presente: chave in window.$chatwoot }).toEqual({
        chave,
        presente: false,
      })
    );
    expect(avisos[0]).toContain('setUser');
  });
});
