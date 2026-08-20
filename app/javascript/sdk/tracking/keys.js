/**
 * Bloco 5.08 (T-C2.1) — o vocabulário do coletor, num lugar só.
 *
 * Os nomes NÃO foram inventados aqui: são exatamente os de
 * `app/services/tracking/origin_attributes.rb` (bloco 1.18), que é o catálogo canônico do
 * backend. Se cada ponta inventasse a sua, o painel mostraria `utm_source` duas vezes com
 * normalizações diferentes — é o conflito nº 5 do plano de tracking.
 */

/** Parâmetros de campanha. Iguais a `UTM_KEYS`. */
export const UTM_KEYS = [
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
];

/** Identificadores de clique. Iguais a `CLICK_ID_KEYS`. */
export const CLICK_ID_KEYS = [
  'gclid',
  'gbraid',
  'wbraid',
  'fbclid',
  'msclkid',
  'ttclid',
];

/**
 * `entry_referrer` e `landing_page` são NOMES NOVOS, e a distinção é o ponto do bloco:
 *
 *  · `page_host`/`page_path` (bloco 1.18) são a página EM QUE O CHAT ABRIU — destino, não
 *    origem. O backend os deriva do `document.location.href` que o SDK já manda.
 *  · `entry_referrer` é o `document.referrer` DE VERDADE, lido na primeira página da sessão.
 *  · `landing_page` é essa primeira página.
 *
 * Chamar o destino de origem é a mentira que a Onda 1 proibiu ao renomear `referrer_host`
 * para `page_host`. Este bloco não a reintroduz: ele traz o dado que faltava, com nome
 * próprio, do único lugar onde ele existe — a landing page, no navegador.
 */
export const ENTRY_KEYS = ['entry_referrer', 'landing_page'];

/** Tudo que o coletor guarda por toque. */
export const TOUCH_KEYS = [...UTM_KEYS, ...CLICK_ID_KEYS, ...ENTRY_KEYS];

/** Prefixos do backend (`CONTACT_PREFIX` / `CONVERSATION_PREFIX`). */
export const FIRST = 'first_';
export const LAST = 'last_';

/** Onde o toque é guardado. Uma chave só, para caber num cookie quando for preciso. */
export const STORE_KEY = 'cw_origin';

/** Teto por valor. Espelha `Tracking::OriginAttributes::MAX_VALUE_LENGTH`. */
export const MAX_VALUE_LENGTH = 255;
