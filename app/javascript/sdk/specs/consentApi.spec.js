/**
 * Bloco 5.09, pela porta pública — e o defeito que este arquivo existe para não deixar voltar.
 *
 * `setConsent` e `updateConsent` passavam `undefined` como validador para `chamadaDeDados`, que
 * chamava `validar()` sem guarda. O `TypeError` caía no `try`, virava `Promise.reject`, e
 * `enfileirar(despachar, …)` **nunca era chamado**: os dois métodos rejeitavam SEMPRE e o
 * consentimento nunca era publicado.
 *
 * MEDIDO EM NAVEGADOR ANTES DE CORRIGIR: `setConsent({ analytics_storage: 'granted' })` deixava
 * o estado em `denied` nos quatro propósitos e o `dataLayer` sem nenhuma entrada de `consent`.
 * O efeito no cliente é o pior possível para o bloco: um site com CMP que ACEITA cookies ficava
 * com a medição inteira desligada — e em silêncio, porque a rejeição só aparece no console.
 *
 * O gate do 5.09 nega por padrão; sem estes métodos funcionando, ele nega para sempre.
 */
describe('5.09 — `setConsent`/`updateConsent` pela API pública', () => {
  let IFrameHelper;

  const carregarPainel = async () => {
    const iframe = document.createElement('iframe');
    iframe.id = 'chatwoot_live_chat_widget';
    iframe.src = 'https://exemplo.test/widget?website_token=tok';
    document.body.appendChild(iframe);
    Object.defineProperty(iframe, 'contentWindow', {
      value: { postMessage: () => {} },
      configurable: true,
    });
    await IFrameHelper.events.loaded({
      config: { authToken: 't', channelConfig: {} },
    });
  };

  beforeEach(async () => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = {};
    // O `dataLayer` do cliente, que já existia antes de nós.
    window.dataLayer = [{ event: 'gtm.js' }];

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation(() => {});

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
    });
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('`setConsent` NÃO rejeita — era o defeito, e ele era total', async () => {
    let rejeitou = null;
    const promessa = window.$chatwoot
      .setConsent({ analytics_storage: 'granted' })
      .catch(erro => {
        rejeitou = erro.message;
      });

    await carregarPainel();
    await promessa;

    expect(rejeitou).toBeNull();
  });

  it('o consentimento pedido é o que fica valendo', async () => {
    const promessa = window.$chatwoot.setConsent({
      analytics_storage: 'granted',
    });
    await carregarPainel();
    await promessa;

    expect(window.$chatwoot.getConsent()).toEqual({
      ad_storage: 'denied',
      ad_user_data: 'denied',
      ad_personalization: 'denied',
      analytics_storage: 'granted',
    });
  });

  it('`updateConsent` aplica a decisão que vem depois da CMP', async () => {
    const defaults = window.$chatwoot.setConsent({});
    const update = window.$chatwoot.updateConsent({ ad_storage: 'granted' });
    await carregarPainel();
    await Promise.all([defaults, update]);

    expect(window.$chatwoot.getConsent().ad_storage).toBe('granted');
  });

  it('publica no `dataLayer` do cliente sem substituí-lo (RC2)', async () => {
    const doCliente = window.dataLayer;

    const promessa = window.$chatwoot.setConsent({
      analytics_storage: 'granted',
    });
    await carregarPainel();
    await promessa;

    expect(window.dataLayer).toBe(doCliente);
    expect(window.dataLayer[0]).toEqual({ event: 'gtm.js' });
    expect(
      window.dataLayer.filter(e => Array.isArray(e) && e[0] === 'consent')
    ).toHaveLength(1);
  });
});
