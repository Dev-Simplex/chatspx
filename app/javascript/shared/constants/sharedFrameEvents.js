export const SDK_SET_BUBBLE_VISIBILITY = 'sdk-set-bubble-visibility';

// Bloco 3.18 — o nome da mensagem que leva, do host para o painel, QUAIS chaves
// de `chatwootSettings` o site esta sobrescrevendo.
//
// Mora aqui, e nao literal nos dois arquivos, porque as duas pontas vivem em
// bundles diferentes (`sdk.js` no site do cliente, `widget` dentro do iframe) e
// um `postMessage` com nome divergente nao produz erro nenhum: o emissor manda,
// ninguem escuta, e o recurso simplesmente nao acontece. Constante compartilhada
// e a unica forma de tornar essa divergencia impossivel em vez de testavel.
export const SDK_APPEARANCE_OVERRIDES = 'appearance-overrides';
