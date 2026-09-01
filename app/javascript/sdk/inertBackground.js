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
 *
 * A SEGUNDA REGRA DURA, que faltava: "celular" NÃO é a condição. A condição é
 * "celular E o painel ocupando a tela". O mesmo holder também é usado como
 * tirinha de não-lidas/campanha no rodapé (`has-unread-view`), e ali a página
 * do cliente está inteira à vista — congelá-la é tirar o site do visitante sem
 * nenhum sinal de por quê. Por isso o que se exporta para os funis é
 * `syncInertBackground`, que RECALCULA a partir do estado real do holder, em
 * vez de um "aplique" e um "solte" que cada chamador teria de acertar sozinho.
 */
import { isMobileViewport } from './viewport';

const MARCA = 'data-woot-inert';

/** Os nós do próprio widget, que jamais podem ficar inertes. */
const NOSSOS = [
  '#cw-bubble-holder',
  '.woot-widget-holder',
  '.woot-widget-bubble',
];

/**
 * As duas classes que tiram o painel do estado "tela cheia", em celular:
 * · `woot--hide`      — painel fechado (`sdk.js`: visibility hidden, fora da tela);
 * · `has-unread-view` — tirinha de não-lidas/campanha no rodapé
 *   (`sdk.js`, @media max-width 767px: height auto, bottom 0, top auto, width auto).
 */
const NAO_E_TELA_CHEIA = ['woot--hide', 'has-unread-view'];

const ehNosso = el => NOSSOS.some(seletor => el.matches?.(seletor));

/**
 * O painel está ocupando a tela AGORA?
 *
 * Lê a classe do holder em vez de medir geometria de propósito: no host o CSS
 * do widget pode ainda não ter sido aplicado quando o toggle roda, e
 * `getBoundingClientRect` devolveria zero para um painel que vai ser tela
 * cheia no frame seguinte. A classe é a fonte que o próprio CSS consulta.
 */
export const isPanelFullscreen = () => {
  if (typeof document === 'undefined') return false;

  const holder = document.querySelector('.woot-widget-holder');
  if (!holder) return false;

  return !NAO_E_TELA_CHEIA.some(classe => holder.classList.contains(classe));
};

/** A página do cliente deve estar inerte neste instante? */
export const shouldInertBackground = () =>
  isMobileViewport() && isPanelFullscreen();

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

/**
 * A única porta que os funis usam: decide a partir do estado, não do evento.
 *
 * Chamar isto é idempotente e seguro em qualquer ordem — o que importa é que
 * rode DEPOIS de o holder ter recebido ou perdido a classe do modo, porque é a
 * classe que ele lê.
 */
export const syncInertBackground = () => {
  if (shouldInertBackground()) applyInertBackground();
  else releaseInertBackground();
};
