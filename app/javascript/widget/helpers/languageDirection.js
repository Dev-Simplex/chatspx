/**
 * Direção do idioma — bloco 2.18.
 *
 * `App.vue` importava esta função de
 * `dashboard/components/widgets/conversation/advancedFilterItems/languages.js`.
 * A função tem três linhas; o arquivo tem 8.537 B, porque carrega junto a
 * tabela de ~200 idiomas do filtro avançado do dashboard — que o widget nunca
 * usa. O import ainda arrastava um chunk inteiro para o first-paint.
 *
 * A lista de RTL é a MESMA do original, copiada linha a linha. Se ela mudar lá,
 * tem de mudar aqui — e é por isso que existe um teste que compara as duas.
 */
const IDIOMAS_RTL = ['ar', 'as', 'fa', 'he', 'ku', 'ur'];

export const getLanguageDirection = (languageCode = '') =>
  IDIOMAS_RTL.includes(languageCode);

export { IDIOMAS_RTL };
