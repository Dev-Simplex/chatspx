/**
 * `inert` no fundo enquanto o widget ocupa a tela — bloco 2.11.
 *
 * Em celular o painel é tela cheia, mas a página do cliente continua atrás dele:
 * sem `inert`, o Tab e o leitor de tela caminham por links e formulários que o
 * visitante não consegue ver. `inert` remove o ramo inteiro da árvore de
 * acessibilidade e da ordem de foco de uma vez.
 *
 * A REGRA DURA: só sai o que ESTE código marcou. Se o site já mantinha um
 * elemento `inert` por conta própria (um menu fechado, um modal do próprio
 * site), fechar o widget não pode desmarcá-lo — seria o widget quebrando a
 * acessibilidade da página que ele visita. Daí a marca `data-woot-inert`.
 */
const MARCA = 'data-woot-inert';

/** Os nós do próprio widget, que jamais podem ficar inertes. */
const NOSSOS = [
  '#cw-bubble-holder',
  '.woot-widget-holder',
  '.woot-widget-bubble',
];

const ehNosso = el => NOSSOS.some(seletor => el.matches?.(seletor));

export const applyInertBackground = () => {
  if (typeof document === 'undefined') return;

  Array.from(document.body.children).forEach(el => {
    if (ehNosso(el)) return;
    // Já era inert por conta do site: não marcamos, e por isso não soltaremos.
    if (el.hasAttribute('inert')) return;

    el.setAttribute('inert', '');
    el.setAttribute(MARCA, '');
  });
};

export const releaseInertBackground = () => {
  if (typeof document === 'undefined') return;

  document.querySelectorAll(`[${MARCA}]`).forEach(el => {
    el.removeAttribute('inert');
    el.removeAttribute(MARCA);
  });
};
