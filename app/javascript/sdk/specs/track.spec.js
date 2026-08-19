import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Bloco 5.16 — `window.$chatwoot.track(name, properties)`.
 *
 * O metodo e publico e chamado de dentro de container do GTM, que executa as tags em sequencia
 * no MESMO contexto: um `throw` aqui impede as tags SEGUINTES do cliente de rodar. Por isso
 * todo exemplo de erro deste arquivo verifica duas coisas — que nao lancou, e que nao mandou.
 */
describe('5.16 — track() no host', () => {
  let enviadas;
  let IFrameHelper;
  let erroNoConsole;

  beforeEach(async () => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = {};
    enviadas = [];

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    erroNoConsole = vi.spyOn(console, 'error').mockImplementation(() => {});

    // A ORDEM IMPORTA — mesma razao de `preBootQueue.spec.js`: `resetModules` faz o entrypoint
    // importar uma instancia NOVA de `IFrameHelper`, e espionar a antiga nao intercepta nada.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
    });
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // A fila pre-boot do 1.23 e o que faz `track()` funcionar quando o site chama antes de o
  // painel montar — que e o caso COMUM no GTM, nao o descuidado.
  const drenar = async () => {
    const iframe = document.createElement('iframe');
    iframe.id = 'chatwoot_live_chat_widget';
    document.body.appendChild(iframe);
    IFrameHelper.events.loaded({
      config: { authToken: 'jwt', channelConfig: {} },
    });
    await Promise.resolve();
    await Promise.resolve();
  };

  const doTrack = () => enviadas.filter(m => m.key === 'track-event');

  // A promessa do 1.23 so resolve QUANDO A MENSAGEM SAI — e antes do boot ela fica na fila.
  // Dar `await` nela antes de drenar trava o exemplo, e essa espera e a prova de que a
  // garantia 3 do bloco 1.23 vale tambem para o `track()`.
  it('manda name, properties e uma chave de idempotencia nao vazia', async () => {
    const promessa = window.$chatwoot.track('chatspx_orcamento_pedido', {
      plano: 'pro',
    });
    await drenar();
    await promessa;

    expect(doTrack()).toHaveLength(1);
    expect(doTrack()[0].value.name).toBe('chatspx_orcamento_pedido');
    expect(doTrack()[0].value.properties).toEqual({ plano: 'pro' });
    expect(typeof doTrack()[0].value.eventKey).toBe('string');
    expect(doTrack()[0].value.eventKey.length).toBeGreaterThan(0);
  });

  // Duas chamadas sao dois FATOS. Se as chaves fossem iguais, o indice unico de 5.03
  // colapsaria as duas numa linha e o cliente contaria metade das conversoes dele.
  it('duas chamadas produzem chaves DIFERENTES', async () => {
    const a = window.$chatwoot.track('chatspx_a');
    const b = window.$chatwoot.track('chatspx_b');
    await drenar();
    await Promise.all([a, b]);

    const chaves = doTrack().map(m => m.value.eventKey);
    expect(chaves).toHaveLength(2);
    expect(chaves[0]).not.toBe(chaves[1]);
  });

  it('properties omitidas viram objeto vazio, nunca undefined', async () => {
    const promessa = window.$chatwoot.track('chatspx_a');
    await drenar();
    await promessa;

    expect(doTrack()[0].value.properties).toEqual({});
  });

  describe('nome fora do formato do contrato', () => {
    const invalidos = [
      ['sem o prefixo', 'orcamento_pedido'],
      ['camelCase', 'chatspx_orcamentoPedido'],
      ['com espaco', 'chatspx_orcamento pedido'],
      ['so o prefixo com maiuscula', 'CHATSPX_ORCAMENTO'],
      ['numero em vez de string', 42],
      ['vazio', ''],
    ];

    it.each(invalidos)(
      'recusa %s sem lancar e sem mandar',
      async (_rotulo, nome) => {
        let lancou = false;
        try {
          await window.$chatwoot.track(nome).catch(() => {});
        } catch {
          lancou = true;
        }
        await drenar();

        expect(lancou).toBe(false);
        expect(doTrack()).toHaveLength(0);
        expect(erroNoConsole).toHaveBeenCalled();
      }
    );

    it('recusa nome acima dos 40 caracteres do GA4', async () => {
      await window.$chatwoot.track(`chatspx_${'a'.repeat(40)}`).catch(() => {});
      await drenar();

      expect(doTrack()).toHaveLength(0);
    });

    it('aceita exatamente 40 caracteres', async () => {
      const nome = `chatspx_${'a'.repeat(32)}`;
      expect(nome).toHaveLength(40);

      const promessa = window.$chatwoot.track(nome);
      await drenar();
      await promessa;

      expect(doTrack()).toHaveLength(1);
    });
  });

  it('properties que nao e objeto e recusado sem lancar', async () => {
    await window.$chatwoot.track('chatspx_a', 'nao sou objeto').catch(() => {});
    await drenar();

    expect(doTrack()).toHaveLength(0);
  });

  // O aceite do 5.05: o verbo antigo continua existindo e continua com a MESMA assinatura.
  it('pushEvent continua existindo e nao virou track', () => {
    expect(typeof IFrameHelper.pushEvent).toBe('function');
    expect(IFrameHelper.pushEvent.length).toBe(1);
  });
});
