/**
 * O breakpoint do widget, em UM lugar.
 *
 * A base tinha TRÊS valores para a mesma pergunta: um limite de 668 px no
 * `IFrameHelper` e outro de 667 px em três media queries do `sdk.js`. Pior que
 * a divergência era a sobreposição — o `sdk.js` usava o mesmo 667 como teto de
 * uma faixa e piso da outra, então naquele pixel exato as duas regras casavam e
 * quem decidia era a ordem no arquivo. E na janela de 668 px o CSS já tratava
 * como desktop enquanto o JS avisava o widget que era celular.
 *
 * Agora é um número só, e as faixas são disjuntas: até 767 é tela cheia, de 768
 * em diante é flutuante.
 */
export const MOBILE_BREAKPOINT = 768;

export const isMobileViewport = () =>
  typeof window !== 'undefined' &&
  typeof window.matchMedia === 'function' &&
  window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`).matches;
