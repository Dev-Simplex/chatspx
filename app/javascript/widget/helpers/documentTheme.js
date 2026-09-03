import { watch } from 'vue';

/**
 * Tema no DOCUMENTO do widget — bloco 2.10.
 *
 * O QUE FALTAVA
 *
 * A classe `dark` era aplicada só nas `div`s raiz de `App.vue`. Isso basta para
 * as utilitárias `dark:` do Tailwind (que é `darkMode: 'class'` e olha qualquer
 * ancestral), mas deixa DUAS coisas de fora:
 *
 *  1. O `<html>`/`<body>` do documento do iframe, que continuam com o fundo
 *     claro do agente de usuário. Enquanto o painel não pinta — carregando, ou
 *     em qualquer área que a `div` não cubra — o que se vê é branco.
 *
 *  2. O `color-scheme`. É ele que diz ao navegador para desenhar em modo
 *     escuro o que a folha de estilo NÃO alcança: a barra de rolagem, o
 *     `caret` do campo de texto, o seletor nativo de data e os controles de
 *     formulário. Sem ele, o widget escuro fica com barra de rolagem clara —
 *     o detalhe que denuncia "tema escuro mal-acabado".
 *
 * O `color-scheme` em si é declarado em CSS (`_tokens.scss`, `:root.dark`), não
 * aqui: é estático e não precisa de JS. Este helper só cuida da classe, que
 * depende de um valor que o servidor não conhece — o tema chega do host pelo
 * `postMessage`, depois de o documento já estar montado.
 */

export const DARK_CLASS = 'dark';

/**
 * @param {boolean} prefersDark  resultado de `useDarkMode().prefersDarkMode`
 * @param {Document} doc         injetável para teste; o documento do iframe
 * @returns {boolean} o estado aplicado, para quem quiser assertar
 */
export const applyDocumentTheme = (prefersDark, doc = document) => {
  const raiz = doc?.documentElement;
  if (!raiz) return false;

  raiz.classList.toggle(DARK_CLASS, !!prefersDark);
  return !!prefersDark;
};

/**
 * Liga uma fonte reativa de "prefere escuro" ao documento.
 *
 * POR QUE ISTO EXISTE EM VEZ DE UM `watch` SOLTO NO `App.vue`
 *
 * A forma óbvia — `watch(prefersDarkMode, applyDocumentTheme, {immediate:true})`
 * — está ERRADA e falha em silêncio: o `watch` do Vue chama o callback com
 * `(novo, antigo, onCleanup)`, então o `antigo` (um booleano) cairia no
 * parâmetro `doc`. Na primeira chamada `antigo` é `undefined` e o default
 * `document` salva; da SEGUNDA em diante `doc` vira `false`, `doc?.documentElement`
 * é `undefined` e a função sai sem fazer nada. Ou seja: funcionaria na abertura
 * e pararia de funcionar exatamente na troca de tema, que é o que o aceite mede.
 *
 * Embrulhar o `watch` aqui deixa o erro impossível de cometer no ponto de uso e
 * dá ao teste um alvo sem precisar montar o `App.vue` inteiro.
 *
 * @param {import('vue').Ref<boolean>} prefersDark
 * @param {Document} doc  injetável para teste
 */
export const watchDocumentTheme = (prefersDark, doc = document) =>
  watch(prefersDark, valor => applyDocumentTheme(valor, doc), {
    immediate: true,
  });

export default { applyDocumentTheme, watchDocumentTheme, DARK_CLASS };
