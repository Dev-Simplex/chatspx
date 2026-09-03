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
