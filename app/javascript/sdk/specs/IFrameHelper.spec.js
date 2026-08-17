import { IFrameHelper } from '../IFrameHelper';

const WIDGET_ORIGIN = 'https://chat.exemplo.com';
const ATACANTE = 'https://evil.exemplo.net';

const payload = message => `chatwoot-widget:${JSON.stringify(message)}`;

describe('IFrameHelper — origem do postMessage no lado do SITE', () => {
  let frame;

  beforeEach(() => {
    frame = document.createElement('iframe');
    frame.id = 'chatwoot_live_chat_widget';
    frame.src = `${WIDGET_ORIGIN}/widget?website_token=abc`;
    document.body.appendChild(frame);
  });

  afterEach(() => {
    frame.remove();
    vi.restoreAllMocks();
  });

  describe('#isTrustedFrameOrigin', () => {
    it('aceita a origem do iframe que o próprio SDK criou', () => {
      expect(IFrameHelper.isTrustedFrameOrigin(WIDGET_ORIGIN)).toBe(true);
    });

    it('recusa qualquer outra origem', () => {
      expect(IFrameHelper.isTrustedFrameOrigin(ATACANTE)).toBe(false);
    });

    it('recusa quando o iframe ainda não existe', () => {
      frame.remove();
      expect(IFrameHelper.isTrustedFrameOrigin(WIDGET_ORIGIN)).toBe(false);
    });
  });

  describe('#onPostMessage', () => {
    it('roda o handler quando a mensagem vem do iframe do widget', () => {
      const handler = vi
        .spyOn(IFrameHelper.events, 'setCampaignReadOn')
        .mockImplementation(() => {});

      IFrameHelper.onPostMessage({
        origin: WIDGET_ORIGIN,
        data: payload({ event: 'setCampaignReadOn' }),
      });

      expect(handler).toHaveBeenCalledTimes(1);
    });

    it('IGNORA a mensagem de origem estranha — o handler não roda', () => {
      const handler = vi
        .spyOn(IFrameHelper.events, 'setCampaignReadOn')
        .mockImplementation(() => {});

      IFrameHelper.onPostMessage({
        origin: ATACANTE,
        data: payload({ event: 'setCampaignReadOn' }),
      });

      expect(handler).not.toHaveBeenCalled();
    });

    it('ignora JSON quebrado sem lançar exceção na página do cliente', () => {
      expect(() =>
        IFrameHelper.onPostMessage({
          origin: WIDGET_ORIGIN,
          data: 'chatwoot-widget:{',
        })
      ).not.toThrow();
    });
  });

  describe('#initPostMessageCommunication', () => {
    it('usa addEventListener e NÃO sequestra o window.onmessage do site', () => {
      // O código antigo fazia `window.onmessage = …`: uma propriedade, um único
      // dono — instalar o widget apagava o handler de mensagem do site.
      // (O jsdom não despacha para `window.onmessage`, então o que se afirma
      //  aqui é a propriedade intacta, que é exatamente o que o antigo quebrava.)
      const doSite = vi.fn();
      window.onmessage = doSite;

      IFrameHelper.initPostMessageCommunication();

      expect(window.onmessage).toBe(doSite);

      const handler = vi
        .spyOn(IFrameHelper.events, 'setCampaignReadOn')
        .mockImplementation(() => {});

      window.dispatchEvent(
        new MessageEvent('message', {
          origin: WIDGET_ORIGIN,
          data: payload({ event: 'setCampaignReadOn' }),
        })
      );

      expect(handler).toHaveBeenCalledTimes(1);

      window.removeEventListener('message', IFrameHelper.onPostMessage);
      window.onmessage = null;
    });
  });
});
