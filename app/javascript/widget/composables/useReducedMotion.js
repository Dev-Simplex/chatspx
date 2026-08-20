/**
 * MOVIMENTO REDUZIDO — bloco 2.08.
 *
 * ── `prefers-reduced-motion` não é "desligar animação" ───────────────────────
 *
 * É *"chegue ao mesmo lugar sem o percurso"*. A distinção importa porque as
 * duas leituras levam a códigos diferentes e só uma delas funciona:
 *
 *   · desligar o movimento de um `scrollTo({ behavior: 'smooth' })` significa
 *     `behavior: 'auto'` — o visitante continua indo parar no fim da lista,
 *     instantaneamente. Correto.
 *   · "desligar a animação" levaria a não rolar, ou a rolar pela metade. O
 *     visitante pediu para ir ao fim e não foi. Isso não é acessibilidade, é
 *     defeito com desculpa.
 *
 * O mesmo vale no CSS: `transition-duration: 0s` preserva o estado final, e é
 * por isso que o bloco usa isso em vez de remover a propriedade que transita.
 *
 * ── Por que é uma função e não um valor lido uma vez ─────────────────────────
 *
 * A preferência muda em tempo de execução — o visitante liga "reduzir
 * movimento" no sistema com o chat aberto. Um valor capturado na montagem
 * ficaria velho, e o widget é uma tela que fica aberta por horas. Cada chamada
 * relê a media query, que é barata: o navegador já mantém o resultado.
 *
 * ── Ausência de `matchMedia` ─────────────────────────────────────────────────
 *
 * jsdom não implementa `matchMedia` por padrão, e o widget também roda dentro
 * de iframes de host com ambientes antigos. Na ausência, a resposta é `false`:
 * assumir que NÃO há preferência mantém o comportamento padrão do produto, e o
 * contrário deixaria todo mundo sem movimento por causa de uma API faltando.
 */

export const CONSULTA_MENOS_MOVIMENTO = '(prefers-reduced-motion: reduce)';

/** O visitante pediu menos movimento? */
export const prefereMenosMovimento = () => {
  if (typeof window === 'undefined') return false;
  if (typeof window.matchMedia !== 'function') return false;
  return window.matchMedia(CONSULTA_MENOS_MOVIMENTO).matches === true;
};

/**
 * O `behavior` para `scrollTo`, respeitando a preferência.
 *
 * `'auto'` é o valor do padrão para "salte", e não uma invenção nossa: é o
 * inicial de `scroll-behavior` na especificação do CSSOM.
 */
export const comportamentoDeRolagem = () =>
  prefereMenosMovimento() ? 'auto' : 'smooth';
