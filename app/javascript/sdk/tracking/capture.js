import { TOUCH_KEYS, STORE_KEY, MAX_VALUE_LENGTH } from './keys';

/**
 * Bloco 5.08 (T-C2.1 + T-C2.2) — a CAPTURA, e ela é a única parte do coletor que roda em
 * toda página.
 *
 * POR QUE ELA NÃO PODE SER SOB DEMANDA. O aceite é "visitante chega por anúncio, navega 5
 * páginas e só então abre o chat". Quando o chat abre, `location.search` já não tem o
 * `gclid` há cinco páginas e o `document.referrer` já é interno. Se a captura só acontecesse
 * ao abrir o chat, a origem já teria sido perdida — não há como recuperá-la depois. Por
 * isso ela é eager, e por isso é escrita para ser pequena: cada byte aqui é baixado por
 * 100% dos visitantes de todos os sites de todos os clientes.
 *
 * O resto do coletor (derivar `_fbc`/`_gcl_aw`, ler cookies por allowlist, pedir
 * `client_id`/`session_id` ao gtag) NÃO roda aqui: só quando o chat abre, e a partir do que
 * esta função guardou. É a divisão que respeita o orçamento de bytes do T-C2.8.
 *
 * NUNCA LANÇA. Está no caminho de boot do site do cliente; um `throw` aqui é um defeito no
 * site dele. Em aba privada do Safari o `localStorage` levanta na ESCRITA — o try/catch não
 * é decorativo.
 */

const truncate = value => String(value ?? '').slice(0, MAX_VALUE_LENGTH);

const readStore = () => {
  try {
    return JSON.parse(window.localStorage.getItem(STORE_KEY)) || {};
  } catch {
    return {};
  }
};

const writeStore = store => {
  try {
    window.localStorage.setItem(STORE_KEY, JSON.stringify(store));
  } catch {
    // Aba privada, storage cheio, storage bloqueado por política do site: a captura
    // simplesmente não persiste. O chat continua funcionando, que é o que importa.
  }
};

/** Os parâmetros de campanha desta URL, já truncados. Vazio quando não há nenhum. */
const paramsFromUrl = search => {
  const query = new URLSearchParams(search);
  return TOUCH_KEYS.reduce((acc, key) => {
    const value = query.get(key);
    if (value) acc[key] = truncate(value);
    return acc;
  }, {});
};

const hostOf = url => {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
};

/**
 * Um referrer é EXTERNO quando existe e não é do próprio site. É metade da regra do
 * T-C2.2: navegação interna não zera a origem.
 */
const hasExternalReferrer = (referrer, host) =>
  Boolean(referrer) && hostOf(referrer) !== host;

/**
 * O toque desta página, ou `null` quando esta página não traz origem nenhuma — que é o caso
 * da 2ª à 5ª página do aceite, e é justamente quando NÃO se pode tocar em `last_`.
 */
const touchFrom = (location, referrer) => {
  const params = paramsFromUrl(location.search);
  const externo = hasExternalReferrer(referrer, location.host);
  if (!Object.keys(params).length && !externo) return null;

  return {
    ...params,
    ...(externo ? { entry_referrer: truncate(referrer) } : {}),
    landing_page: truncate(`${location.origin}${location.pathname}`),
    ts: Date.now(),
  };
};

/**
 * Captura a origem desta página.
 *
 * Regras (T-C2.2), e as duas existem por erro clássico de mercado:
 *  · `first` é WRITE-ONCE — a primeira origem da pessoa nunca é reescrita;
 *  · `last` só é sobrescrito quando a página traz parâmetro de campanha OU referrer
 *    externo. Navegação interna não zera nada.
 *
 * Devolve o registro guardado (útil para teste e diagnóstico), nunca lança.
 */
export const captureOrigin = ({
  location = window.location,
  referrer = window.document.referrer,
} = {}) => {
  try {
    const touch = touchFrom(location, referrer);
    if (!touch) return readStore();

    const store = readStore();
    const next = { ...store, last: touch };
    if (!store.first) next.first = touch;

    writeStore(next);
    return next;
  } catch {
    return {};
  }
};

/** O registro guardado, sem escrever nada. */
export const storedOrigin = () => readStore();

// Nada de export "para teste": além de ser API que ninguém usa em produção, cada símbolo
// exportado é byte que 100% dos visitantes baixam. O spec exercita pela porta pública.
