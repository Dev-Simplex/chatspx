import { IFrameHelper } from 'widget/helpers/utils';

/**
 * `Esc` fecha o widget — bloco 2.11.
 *
 * O listener é do DOCUMENTO, e não de um elemento, e a razão é medida:
 * `ViewWithHeader.vue` já trazia `@keydown.esc="closeWindow"` num `<div>`, e
 * `keydown` só chega ali se o foco já estiver dentro dele. Logo depois de abrir,
 * o foco está no `<body>` do iframe — a tecla não encontrava handler nenhum e o
 * widget não fechava. Um `<div>` não é ancestral do `<body>`.
 *
 * `Escape` apenas, nunca o `Esc` de navegador antigo: a base já roda em
 * navegadores que emitem o nome novo, e aceitar os dois faria o teste passar por
 * um caminho que ninguém exercita.
 */
export const registerCloseOnEscape = () => {
  const onKeydown = event => {
    if (event.key !== 'Escape') return;
    IFrameHelper.sendMessage({ event: 'closeWindow' });
  };

  document.addEventListener('keydown', onKeydown);
  return () => document.removeEventListener('keydown', onKeydown);
};
