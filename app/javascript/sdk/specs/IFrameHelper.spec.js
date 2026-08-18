import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

// Bloco 1.03 — "Launcher e painel derivam da mesma fonte; nenhuma fórmula de
// contraste em JS".
//
// O launcher vive no `document` do site do cliente e o painel vive num iframe.
// Antes deste bloco, cada lado decidia a própria cor de texto: o painel por uma
// heurística YIQ (limiar 186) e o host com `isWidgetColorLighter` (brilho
// 299/587/114, limiar 225). Duas heurísticas diferentes, nenhuma WCAG — e é por
// isso que header e launcher discordavam. O bloco 1.04 removeu a primeira do
// código; a segunda saiu aqui, no 1.03.
//
// Aqui o teste não verifica "tem alguma cor": ele verifica que o VALOR que o
// launcher pinta é o MESMO objeto de tokens que o servidor mandou para o
// painel, token a token.

// O payload que o `WidgetTokens` do servidor produz para `#009CE0` — copiado da
// saída real do ERB, não inventado (ver `spec/services/widget_tokens_spec.rb`).
const SERVER_TOKENS = {
  '--w-brand': '#009ce0',
  '--w-brand-hover': '#008cca',
  '--w-brand-active': '#0080b8',
  '--w-on-brand': '#000000',
  '--w-brand-readable': '#0079ad',
  '--w-brand-readable-dark': '#009ce0',
  '--w-focus-ring-color': '#0079ad',
};

const bootHost = () => {
  document.body.innerHTML = '';
  window.$chatwoot = {
    position: 'right',
    hideMessageBubble: false,
    widgetStyle: 'standard',
    type: 'standard',
    baseUrl: 'https://chat.example.com',
  };
};

describe('applyWidgetTokens — a fronteira do postMessage', () => {
  let applyWidgetTokens;

  beforeEach(async () => {
    vi.resetModules();
    bootHost();
    ({ applyWidgetTokens } = await import('../IFrameHelper'));
  });

  it('escreve os sete tokens do servidor no elemento', () => {
    const el = document.createElement('div');

    const applied = applyWidgetTokens(el, SERVER_TOKENS);

    expect(applied).toEqual(SERVER_TOKENS);
    expect(el.style.getPropertyValue('--w-brand')).toBe('#009ce0');
    expect(el.style.getPropertyValue('--w-on-brand')).toBe('#000000');
    expect(el.style.getPropertyValue('--w-focus-ring-color')).toBe('#0079ad');
  });

  it('recusa valor que não é cor — postMessage é superfície de entrada', () => {
    const el = document.createElement('div');

    const applied = applyWidgetTokens(el, {
      '--w-brand': 'red;background-image:url(https://evil.example/x.png)',
      '--w-on-brand': 'expression(alert(1))',
      '--w-brand-hover': '#00ff00',
    });

    expect(applied).toEqual({ '--w-brand-hover': '#00ff00' });
    expect(el.style.getPropertyValue('--w-brand')).toBe('');
    expect(el.style.getPropertyValue('--w-on-brand')).toBe('');
  });

  it('recusa nome que não está na lista fechada', () => {
    const el = document.createElement('div');

    const applied = applyWidgetTokens(el, { '--evil': '#000000' });

    expect(applied).toEqual({});
    expect(el.style.getPropertyValue('--evil')).toBe('');
  });
});

describe('IFrameHelper.onLoad — o launcher pinta com o que o painel recebeu', () => {
  let IFrameHelper;

  beforeEach(async () => {
    vi.resetModules();
    bootHost();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    const iframe = document.createElement('iframe');
    iframe.id = 'chatwoot_live_chat_widget';
    document.body.appendChild(iframe);
  });

  it('hospeda os tokens no bubbleHolder, com os mesmos valores do servidor', () => {
    IFrameHelper.onLoad({ widgetColor: '#009CE0', tokens: SERVER_TOKENS });

    const holder = document.getElementById('cw-bubble-holder');
    expect(holder).not.toBeNull();
    Object.entries(SERVER_TOKENS).forEach(([name, value]) => {
      expect(holder.style.getPropertyValue(name)).toBe(value);
    });
  });

  it('pinta a bolha com --w-brand, não com uma segunda leitura de widgetColor', () => {
    IFrameHelper.onLoad({ widgetColor: '#ff0000', tokens: SERVER_TOKENS });

    const bubble = document.querySelector('.woot-widget-bubble');
    const holder = document.getElementById('cw-bubble-holder');

    // `widgetColor` divergente de propósito: se o launcher lesse a cor por
    // fora do token, apareceria vermelho em algum destes três lugares.
    //
    // Este teste mudou no bloco 1.05, e a mudança é o ponto: ele ASSERE A
    // AUSÊNCIA do estilo inline. Enquanto `chatIcon.style.background` existia,
    // o inline vencia a folha e mascarava o `#2dc46f` cravado no `:hover` — o
    // literal só apareceria em produção, no mouse do visitante. Sem inline, a
    // cor de repouso e a de hover saem da mesma var, e o valor efetivo é
    // medido em Chromium real por `sdk-launcher-hover.spec.js`.
    expect(bubble.style.background).toBe('');
    // `null`, não "string sem vermelho": o SDK não escreve atributo `style`
    // nenhum no lançador. É a forma mais forte de dizer que o inline saiu.
    expect(bubble.getAttribute('style')).toBeNull();
    expect(holder.style.getPropertyValue('--w-brand')).toBe('#009ce0');
  });

  it('a marca clara vira classe --lighter pela decisão do SERVIDOR', () => {
    // #009CE0 tem L = 0,2916 > 0,17913, então `--w-on-brand` veio `#000000`.
    // A antiga `isWidgetColorLighter('#009CE0')` daria FALSE (brilho 129 < 225)
    // e o launcher continuaria com ícone branco a 3,07:1.
    IFrameHelper.onLoad({ widgetColor: '#009CE0', tokens: SERVER_TOKENS });

    const bubble = document.querySelector('.woot-widget-bubble');
    expect(bubble.className).toContain('woot-widget-bubble-color--lighter');
  });

  it('a marca escura NÃO vira --lighter', () => {
    IFrameHelper.onLoad({
      widgetColor: '#1a1a1a',
      tokens: {
        ...SERVER_TOKENS,
        '--w-brand': '#1a1a1a',
        '--w-on-brand': '#ffffff',
      },
    });

    const bubble = document.querySelector('.woot-widget-bubble');
    expect(bubble.className).not.toContain('woot-widget-bubble-color--lighter');
  });
});

describe('loadedEventConfig — a ponte carrega a fonte, não uma cópia', () => {
  beforeEach(() => {
    vi.resetModules();
    bootHost();
  });

  it('entrega ao host exatamente os tokens que o servidor escreveu no canal', async () => {
    window.chatwootWebChannel = {
      widgetColor: '#009CE0',
      tokens: SERVER_TOKENS,
    };
    const { loadedEventConfig } = await import(
      '../../widget/helpers/IframeEventHelper'
    );

    expect(loadedEventConfig().config.tokens).toEqual(SERVER_TOKENS);
  });

  it('sem tokens no canal (HTML antigo em cache) lê o :root que o painel pinta', async () => {
    window.chatwootWebChannel = { widgetColor: '#009CE0' };
    document.documentElement.style.setProperty('--w-brand', '#009ce0');
    document.documentElement.style.setProperty('--w-on-brand', '#000000');
    const { loadedEventConfig } = await import(
      '../../widget/helpers/IframeEventHelper'
    );

    expect(loadedEventConfig().config.tokens).toEqual({
      '--w-brand': '#009ce0',
      '--w-on-brand': '#000000',
    });
    document.documentElement.removeAttribute('style');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// UNIÃO DE DOIS BLOCOS NESTE ARQUIVO — leia antes de mexer
//
// Este arquivo foi criado DUAS VEZES, em trilhas paralelas, com o mesmo caminho
// e conteúdos disjuntos: a trilha do widget escreveu os testes do bloco 1.03
// (acima) e a trilha do bridge escreveu os do 1.09 (abaixo). O merge acusou
// conflito de add/add e o coordenador resolveu por UNIÃO, não por escolha:
// ficar com um dos lados apagaria silenciosamente 7 ou 9 asserções que testam
// coisas diferentes do mesmo módulo.
//
//   1.03 — `applyWidgetTokens`: os 7 tokens do servidor atravessam o
//          postMessage e são escritos no elemento, token a token.
//   1.09 — `isTrustedFrameOrigin` / `onPostMessage` /
//          `initPostMessageCommunication`: a origem da mensagem é conferida e
//          o `window.onmessage` do site não é sequestrado.
//
// Se um futuro merge voltar a conflitar aqui, a resolução correta continua
// sendo união. Some as duas partes; não escolha uma.
// ─────────────────────────────────────────────────────────────────────────────

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
