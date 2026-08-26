/**
 * i18n do widget — SOB DEMANDA (bloco 2.18).
 *
 * O que este arquivo fazia até aqui: 40 `import` estáticos de JSON. Os 40
 * viajavam no fecho de first-paint, medidos em 201.758 B renderizados —
 * 7,3% de todo o JS eager do widget — para que o visitante lesse UM deles.
 * Um visitante brasileiro baixava tailandês, hebraico e islandês antes de
 * ver a primeira bolha.
 *
 * O que ele faz agora: `en` continua ESTÁTICO, porque é o `fallbackLocale`
 * e porque um widget sem nenhuma string é um widget quebrado; os outros 39
 * viram `import()` dinâmico, um chunk por idioma, buscados só quando aquele
 * idioma é de fato o do painel.
 *
 * O MAPA É EXPLÍCITO, e não `import.meta.glob`, por duas razões medidas:
 *
 *   1. `app/javascript/widget/i18n/locale/` tem 56 arquivos e este índice
 *      sempre expôs 40. Um glob passaria a expor os 16 que nunca estiveram
 *      no contrato — mudança de comportamento escondida numa otimização.
 *   2. O mapa é grepável. `loadLocaleMessages('pt_BR')` cai numa linha que
 *      se lê; um glob cai numa string montada em tempo de execução, e o
 *      próximo a mexer aqui não tem como saber o que existe.
 *
 * O `default` continua sendo o objeto de mensagens que `createI18n` recebe —
 * só que agora ele nasce com `en` e cresce por `setLocaleMessage()`. Quem
 * importa este `default` fora do build do widget (`histoire.setup.ts`)
 * continua funcionando; as histórias renderizam em inglês, que é o que elas
 * já faziam por não trocar de locale.
 */
import en from './locale/en.json';

/**
 * Os 40 idiomas que este índice sempre expôs, um `import()` por idioma.
 * NÃO trocar por glob — ver o cabeçalho.
 */
const LOCALE_LOADERS = {
  ar: () => import('./locale/ar.json'),
  bg: () => import('./locale/bg.json'),
  ca: () => import('./locale/ca.json'),
  cs: () => import('./locale/cs.json'),
  da: () => import('./locale/da.json'),
  de: () => import('./locale/de.json'),
  el: () => import('./locale/el.json'),
  en: () => Promise.resolve({ default: en }),
  es: () => import('./locale/es.json'),
  fa: () => import('./locale/fa.json'),
  fi: () => import('./locale/fi.json'),
  fr: () => import('./locale/fr.json'),
  he: () => import('./locale/he.json'),
  hi: () => import('./locale/hi.json'),
  hu: () => import('./locale/hu.json'),
  id: () => import('./locale/id.json'),
  is: () => import('./locale/is.json'),
  it: () => import('./locale/it.json'),
  ja: () => import('./locale/ja.json'),
  ko: () => import('./locale/ko.json'),
  lt: () => import('./locale/lt.json'),
  lv: () => import('./locale/lv.json'),
  ml: () => import('./locale/ml.json'),
  nl: () => import('./locale/nl.json'),
  no: () => import('./locale/no.json'),
  pl: () => import('./locale/pl.json'),
  pt: () => import('./locale/pt.json'),
  pt_BR: () => import('./locale/pt_BR.json'),
  ro: () => import('./locale/ro.json'),
  ru: () => import('./locale/ru.json'),
  sk: () => import('./locale/sk.json'),
  sr: () => import('./locale/sr.json'),
  sv: () => import('./locale/sv.json'),
  ta: () => import('./locale/ta.json'),
  th: () => import('./locale/th.json'),
  tr: () => import('./locale/tr.json'),
  uk: () => import('./locale/uk.json'),
  vi: () => import('./locale/vi.json'),
  zh_CN: () => import('./locale/zh_CN.json'),
  zh_TW: () => import('./locale/zh_TW.json'),
};

/** O idioma que viaja no bundle de first-paint e serve de `fallbackLocale`. */
export const FALLBACK_LOCALE = 'en';

/** Os 40 códigos que este índice expõe. Mesma lista de sempre. */
export const AVAILABLE_LOCALES = Object.keys(LOCALE_LOADERS);

export const hasLocale = locale =>
  Object.prototype.hasOwnProperty.call(LOCALE_LOADERS, locale);

/**
 * Busca as mensagens de UM idioma.
 *
 * Devolve `null` — e não lança — para código desconhecido e para falha de
 * rede: um chunk de idioma que não chega tem de degradar para o `en` que já
 * está em memória, nunca derrubar o painel do visitante. O erro vai ao
 * console porque silêncio aqui é o que transforma "o widget está em inglês"
 * num chamado de suporte sem pista.
 */
export const loadLocaleMessages = async locale => {
  if (!hasLocale(locale)) return null;
  try {
    const mod = await LOCALE_LOADERS[locale]();
    return mod.default ?? mod;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(`[chatwoot] falha ao carregar o idioma "${locale}":`, error);
    return null;
  }
};

/**
 * As mensagens EAGER. Só o fallback — o resto entra por
 * `setLocaleMessage()` conforme `loadLocaleMessages()` resolve.
 */
export default { en };
