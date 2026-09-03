/**
 * VERIFICAÇÃO DESCARTÁVEL — este arquivo NÃO é commitado neste branch.
 *
 * O aceite do 4.20 pede: "`Esc` fecha o painel aberto por auto-open e devolve o
 * foco ao lançador (2.11)". O 2.11 está fechado, mas no branch `o5-composer`, que
 * ainda não entrou em `redesenho-integra`. Aqui o `closeOnEscape.js` dele é
 * colocado ao lado do 4.20 só para esta execução, para que a afirmação do
 * relatório tenha mecanismo e não dedução.
 */
import { registerCloseOnEscape } from 'widget/bridge/closeOnEscape';
import { IFrameHelper as PonteDoWidget } from 'widget/helpers/utils';

vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { sendMessage: vi.fn() },
}));

describe('4.20 × 2.11 — o painel aberto SOZINHO fecha no Esc', () => {
  let bubbleHelpers;
  let IFrameHelper;
  let holder;

  const larguraDaTela = largura => {
    window.matchMedia = query => ({
      matches: largura <= Number(/max-width:\s*(\d+)px/.exec(query)?.[1] ?? 0),
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
    });
  };

  beforeEach(async () => {
    vi.resetModules();
    vi.useFakeTimers();
    document.body.innerHTML = '';
    sessionStorage.clear();
    document.cookie = 'cw_approach=; Max-Age=0';
    document.cookie = 'cw_teaser_dismissed=; Max-Age=0';
    Object.defineProperty(document.documentElement, 'scrollHeight', {
      value: 2000,
      configurable: true,
    });
    window.innerHeight = 1000;
    window.scrollY = 0;
    larguraDaTela(1280);
    global.requestAnimationFrame = cb => cb();

    window.$chatwoot = { isOpen: false, hideMessageBubble: false, baseDomain: undefined };
    window.chatwootWebChannel = {
      welcomeTagline: 'Fale com a gente',
      widgetTriggers: { enabled: true, approach: 'aggressive' },
    };

    bubbleHelpers = await import('../bubbleHelpers');
    ({ IFrameHelper } = await import('../IFrameHelper'));
    document.body.appendChild(bubbleHelpers.chatBubble);
    document.body.appendChild(bubbleHelpers.closeBubble);

    // `closeWindow` tira a classe de nao-lidas do holder do painel; sem ele no DOM
    // o teste morre antes de chegar ao que mede.
    const painel = document.createElement('div');
    painel.className = 'woot-widget-holder';
    document.body.appendChild(painel);

    holder = document.createElement('div');
    document.body.appendChild(holder);
    IFrameHelper.sendMessage = () => {};
    IFrameHelper.events.onBubbleToggle = () => {};
  });

  afterEach(() => vi.useRealTimers());

  it('auto-open → Esc → painel fechado e foco no lançador', () => {
    // 1. O painel abre SOZINHO, pelo caminho real do 4.20.
    IFrameHelper.montarTeaserSeConfigurado(holder);
    window.scrollY = 400;
    window.dispatchEvent(new Event('scroll'));
    vi.advanceTimersByTime(8000);
    expect(window.$chatwoot.isOpen).toBe(true);

    // 2. Esc DENTRO do iframe. O listener do 2.11 é do documento — não depende de
    //    onde o foco está, que é exatamente o defeito que aquele bloco corrigiu.
    const desligar = registerCloseOnEscape();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    desligar();
    expect(PonteDoWidget.sendMessage).toHaveBeenCalledWith({
      event: 'closeWindow',
    });

    // 3. O host atende `closeWindow` — é o handler real do IFrameHelper.
    IFrameHelper.events.closeWindow();

    expect(window.$chatwoot.isOpen).toBe(false);
    expect(document.activeElement).toBe(bubbleHelpers.chatBubble);
  });
});
