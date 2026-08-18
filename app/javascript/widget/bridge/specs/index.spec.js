import { handleFrameMessage, registerBridgeListeners } from '../index';
import {
  getParentOrigin,
  getParentTargetOrigin,
  isTrustedOrigin,
} from '../origin';
import { sendMessage } from 'widget/helpers/utils';

const HOST = 'https://loja.exemplo.com';
const ATACANTE = 'https://evil.exemplo.net';

const setReferrer = value => {
  Object.defineProperty(document, 'referrer', {
    value,
    configurable: true,
  });
};

const payload = message => `chatwoot-widget:${JSON.stringify(message)}`;

const buildContext = () => ({
  $store: { dispatch: vi.fn() },
  $route: { name: 'home' },
});

describe('bridge — origem do postMessage', () => {
  beforeEach(() => {
    setReferrer(`${HOST}/carrinho`);
    delete window.ReactNativeWebView;
  });

  afterEach(() => {
    setReferrer('');
  });

  describe('#getParentOrigin', () => {
    it('deriva a origem do embutidor do document.referrer', () => {
      expect(getParentOrigin()).toBe(HOST);
    });

    it('devolve null quando o site suprime o referrer', () => {
      setReferrer('');
      expect(getParentOrigin()).toBeNull();
    });
  });

  describe('#getParentTargetOrigin', () => {
    it('nunca é "*" quando a origem do embutidor é conhecida', () => {
      expect(getParentTargetOrigin()).toBe(HOST);
    });

    it('cai para "*" só quando não há referrer — comportamento de hoje, documentado', () => {
      setReferrer('');
      expect(getParentTargetOrigin()).toBe('*');
    });
  });

  describe('#sendMessage', () => {
    it('posta para a origem real do embutidor, não para "*"', () => {
      const postMessage = vi
        .spyOn(window.parent, 'postMessage')
        .mockImplementation(() => {});

      sendMessage({ event: 'setUnreadMode' });

      expect(postMessage).toHaveBeenCalledWith(
        'chatwoot-widget:{"event":"setUnreadMode"}',
        HOST
      );
      postMessage.mockRestore();
    });
  });

  describe('#isTrustedOrigin', () => {
    it('aceita a origem do embutidor e recusa qualquer outra', () => {
      expect(isTrustedOrigin(HOST)).toBe(true);
      expect(isTrustedOrigin(ATACANTE)).toBe(false);
    });

    it('aceita tudo dentro do React Native WebView, que não tem origem real', () => {
      window.ReactNativeWebView = { postMessage: vi.fn() };
      expect(isTrustedOrigin(ATACANTE)).toBe(true);
    });
  });

  describe('#handleFrameMessage', () => {
    it('atende a mensagem que veio do embutidor', () => {
      const ctx = buildContext();
      const atendida = handleFrameMessage(
        {
          origin: HOST,
          data: payload({ event: 'set-color-scheme', darkMode: 'dark' }),
        },
        ctx
      );

      expect(atendida).toBe(true);
      expect(ctx.$store.dispatch).toHaveBeenCalledWith(
        'appConfig/setColorScheme',
        'dark'
      );
    });

    it('IGNORA postMessage de origem estranha — nenhum handler roda', () => {
      const ctx = buildContext();
      const atendida = handleFrameMessage(
        {
          origin: ATACANTE,
          data: payload({ event: 'set-color-scheme', darkMode: 'dark' }),
        },
        ctx
      );

      expect(atendida).toBe(false);
      expect(ctx.$store.dispatch).not.toHaveBeenCalled();
    });

    it('ignora payload sem o prefixo do widget', () => {
      const ctx = buildContext();
      expect(
        handleFrameMessage(
          { origin: HOST, data: '{"event":"set-color-scheme"}' },
          ctx
        )
      ).toBe(false);
      expect(ctx.$store.dispatch).not.toHaveBeenCalled();
    });

    it('ignora JSON quebrado sem deixar a exceção subir', () => {
      const ctx = buildContext();
      expect(
        handleFrameMessage({ origin: HOST, data: 'chatwoot-widget:{' }, ctx)
      ).toBe(false);
    });

    it('ignora evento que não está no contrato', () => {
      const ctx = buildContext();
      expect(
        handleFrameMessage(
          { origin: HOST, data: payload({ event: 'evento-inventado' }) },
          ctx
        )
      ).toBe(false);
      expect(ctx.$store.dispatch).not.toHaveBeenCalled();
    });
  });

  describe('#registerBridgeListeners', () => {
    it('atende a mensagem real do embutidor e descarta a de origem estranha', () => {
      const ctx = buildContext();
      const listener = registerBridgeListeners(ctx);

      window.dispatchEvent(
        new MessageEvent('message', {
          origin: ATACANTE,
          data: payload({ event: 'set-color-scheme', darkMode: 'dark' }),
        })
      );
      expect(ctx.$store.dispatch).not.toHaveBeenCalled();

      window.dispatchEvent(
        new MessageEvent('message', {
          origin: HOST,
          data: payload({ event: 'set-color-scheme', darkMode: 'light' }),
        })
      );
      expect(ctx.$store.dispatch).toHaveBeenCalledWith(
        'appConfig/setColorScheme',
        'light'
      );

      window.removeEventListener('message', listener);
    });
  });
});
