/**
 * Mecanismo de aceite do bloco 2.11, metade do SITE (SDK).
 *
 * `inert` no fundo em mobile: com o widget em tela cheia, o resto da página do
 * cliente continua alcançável por Tab e pelo leitor de tela — o visitante
 * navega "atrás" de um painel que ocupa a tela inteira.
 *
 * A regra dura aqui é NÃO ROUBAR ESTADO ALHEIO: se o site já tinha um elemento
 * `inert` por conta própria, fechar o widget não pode desmarcá-lo. Só sai o que
 * este código marcou.
 */
import {
  applyInertBackground,
  releaseInertBackground,
  isPanelFullscreen,
  shouldInertBackground,
  syncInertBackground,
} from '../inertBackground';

const criarPagina = () => {
  document.body.innerHTML = '';
  const conteudo = document.createElement('main');
  const rodape = document.createElement('footer');
  const jaInerte = document.createElement('aside');
  jaInerte.setAttribute('inert', '');
  const holder = document.createElement('div');
  holder.id = 'cw-bubble-holder';
  const widget = document.createElement('div');
  widget.className = 'woot-widget-holder';

  [conteudo, rodape, jaInerte, holder, widget].forEach(el =>
    document.body.appendChild(el)
  );
  return { conteudo, rodape, jaInerte, holder, widget };
};

const larguraDaTela = largura => {
  window.matchMedia = query => ({
    matches: Number(/max-width:\s*(\d+)px/.exec(query)?.[1] ?? 0) >= largura,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  });
};

describe('2.11 — inert no fundo', () => {
  it('marca o conteúdo do site e poupa os nós do widget', () => {
    const { conteudo, rodape, holder, widget } = criarPagina();

    applyInertBackground();

    expect(conteudo.hasAttribute('inert')).toBe(true);
    expect(rodape.hasAttribute('inert')).toBe(true);
    expect(holder.hasAttribute('inert')).toBe(false);
    expect(widget.hasAttribute('inert')).toBe(false);
  });

  it('ao liberar, devolve a página ao que era', () => {
    const { conteudo, rodape } = criarPagina();

    applyInertBackground();
    releaseInertBackground();

    expect(conteudo.hasAttribute('inert')).toBe(false);
    expect(rodape.hasAttribute('inert')).toBe(false);
  });

  it('NÃO desmarca o que já era inert do site', () => {
    const { jaInerte } = criarPagina();

    applyInertBackground();
    releaseInertBackground();

    expect(jaInerte.hasAttribute('inert')).toBe(true);
  });

  it('aplicar duas vezes e liberar uma devolve a página — sem inert grudado', () => {
    const { conteudo } = criarPagina();

    applyInertBackground();
    applyInertBackground();
    releaseInertBackground();

    expect(conteudo.hasAttribute('inert')).toBe(false);
  });
});

/**
 * A guarda "celular E tela cheia". `isMobileViewport()` sozinho era a condição
 * antiga, e ela é falsa exatamente quando o holder está no rodapé como tirinha
 * de não-lidas — o momento em que a página do cliente está inteira à vista.
 */
describe('2.11 — a guarda lê o estado do painel, não só a largura', () => {
  it('sem holder no documento não há tela cheia (nem `inert`)', () => {
    document.body.innerHTML = '';
    larguraDaTela(375);

    expect(isPanelFullscreen()).toBe(false);
    expect(shouldInertBackground()).toBe(false);
  });

  it('holder escondido (`woot--hide`) não é tela cheia', () => {
    const { widget } = criarPagina();
    widget.className = 'woot-widget-holder woot--hide woot-elements--right';
    larguraDaTela(375);

    expect(isPanelFullscreen()).toBe(false);
    expect(shouldInertBackground()).toBe(false);
  });

  it('holder em modo não-lidas (`has-unread-view`) não é tela cheia', () => {
    const { widget } = criarPagina();
    widget.className =
      'woot-widget-holder has-unread-view woot-elements--right';
    larguraDaTela(375);

    expect(isPanelFullscreen()).toBe(false);
    expect(shouldInertBackground()).toBe(false);
  });

  it('holder aberto e sem tirinha É tela cheia — mas só vale em celular', () => {
    const { widget } = criarPagina();
    widget.className = 'woot-widget-holder woot-elements--right';

    larguraDaTela(375);
    expect(isPanelFullscreen()).toBe(true);
    expect(shouldInertBackground()).toBe(true);

    larguraDaTela(1280);
    expect(isPanelFullscreen()).toBe(true);
    expect(shouldInertBackground()).toBe(false);
  });

  it('syncInertBackground aplica e SOLTA conforme o estado, sem chamador decidir', () => {
    const { conteudo, widget } = criarPagina();
    widget.className = 'woot-widget-holder woot-elements--right';
    larguraDaTela(375);

    syncInertBackground();
    expect(conteudo.hasAttribute('inert')).toBe(true);

    // A tirinha chega por cima de um `inert` já aplicado: recalcular solta.
    widget.classList.add('has-unread-view');
    syncInertBackground();
    expect(conteudo.hasAttribute('inert')).toBe(false);

    // E volta a marcar quando o painel volta a ocupar a tela.
    widget.classList.remove('has-unread-view');
    syncInertBackground();
    expect(conteudo.hasAttribute('inert')).toBe(true);
  });
});
