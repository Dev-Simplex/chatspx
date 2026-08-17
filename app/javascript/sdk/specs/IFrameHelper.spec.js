import { describe, it, expect, beforeEach, vi } from 'vitest';

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
