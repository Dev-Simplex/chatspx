/**
 * O breakpoint do widget, em UM lugar.
 *
 * A base tem três valores para a mesma pergunta — `max-width: 668px` em
 * `IFrameHelper.js:480` e `667px` em três media queries de `sdk.js` —, e um
 * visitante com a janela em 668 px cai num estado que ninguém desenhou. O bloco
 * 2.09 unifica em **768**; este módulo é a fonte, e o 2.11 já nasce consumindo
 * dela em vez de acrescentar um quarto número.
 */
export const MOBILE_BREAKPOINT = 768;

export const isMobileViewport = () =>
  typeof window !== 'undefined' &&
  typeof window.matchMedia === 'function' &&
  window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`).matches;
