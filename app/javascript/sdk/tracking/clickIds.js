/**
 * Bloco 5.08 (T-C2.3) — `_fbc` e `_gcl_aw` no formato OFICIAL, e a regra que impede o pior
 * erro possível nesta camada: **nunca fabricar `_fbc` sem `fbclid` real**.
 *
 * Um `_fbc` inventado não melhora atribuição — ele envia à Meta uma correspondência que
 * nunca existiu, e o custo cai no cliente (dado sujo na conta de anúncios dele, não na
 * nossa). Por isso toda derivação aqui exige o identificador de clique de verdade.
 *
 * PREFERIMOS SEMPRE O COOKIE REAL. Quando o Pixel/gtag do cliente já escreveu `_fbc` ou
 * `_gcl_aw`, é esse valor que vale: ele foi escrito por quem conhece o domínio em que o
 * cookie mora. A derivação é o caminho de recuperação, para quando o cliente não tem o
 * Pixel na página (que é justamente o caso em que a nossa camada server-side importa).
 */

/** Janela do Google para o `gclid` e da Meta para o `fbc`: 90 dias. */
export const TTL_MS = 90 * 24 * 60 * 60 * 1000;

/**
 * `subdomainIndex` do formato `fb.{subdomainIndex}.{timestamp}.{fbclid}`: a Meta o define
 * como o índice do domínio em que o cookie está gravado, contando a partir do TLD —
 * `com` = 0, `exemplo.com` = 1, `www.exemplo.com` = 2.
 *
 * LIMITAÇÃO DECLARADA: contar rótulos erra em ccSLD. Em `loja.com.br` o domínio registrável
 * tem três rótulos e o cookie mora nele, então o índice correto seria 1 — e a contagem dá 2.
 * Não há como acertar isso sem a Public Suffix List, que são ~40 kB e não cabem no SDK.
 * É por isso que o cookie real tem precedência: quando o Pixel existe, este cálculo não é
 * usado. Quando não existe, um índice off-by-one é degradação conhecida, não silenciosa.
 */
export const subdomainIndex = host =>
  Math.max(String(host || '').split('.').length - 1, 0);

const isFresh = (timestamp, now) =>
  Boolean(timestamp) && now - timestamp < TTL_MS;

/**
 * Deriva `_fbc` de um `fbclid` REAL. Devolve `null` quando não há fbclid, quando ele já
 * venceu a janela de 90 dias, ou quando faltam dados para montar o formato.
 */
export const deriveFbc = ({ fbclid, timestamp, host, now = Date.now() }) => {
  if (!fbclid || !isFresh(timestamp, now)) return null;

  return `fb.${subdomainIndex(host)}.${timestamp}.${fbclid}`;
};

/** Deriva `_gcl_aw` de um `gclid` real, no formato `GCL.{unix}.{gclid}` (segundos). */
export const deriveGclAw = ({ gclid, timestamp, now = Date.now() }) => {
  if (!gclid || !isFresh(timestamp, now)) return null;

  return `GCL.${Math.floor(timestamp / 1000)}.${gclid}`;
};

/**
 * Os dois identificadores, com o COOKIE REAL tendo precedência sobre a derivação.
 * `cookies` é o que a allowlist leu; `touch` é o toque guardado pela captura.
 */
export const clickIdentifiers = ({
  touch = {},
  cookies = {},
  host,
  now = Date.now(),
}) => {
  // Desestruturação com renome, e não `cookies._fbc`: o `no-underscore-dangle` do projeto
  // reprova a forma com ponto (e o `dot-notation` reprova a com colchete), enquanto
  // destructuring é explicitamente permitido pela regra. Nome de cookie começando com `_`
  // não é escolha nossa — é o que a Meta e o Google escrevem.
  const { _fbc: cookieFbc, _gcl_aw: cookieGclAw, _fbp: cookieFbp } = cookies;

  const fbc =
    cookieFbc ||
    deriveFbc({ fbclid: touch.fbclid, timestamp: touch.ts, host, now });
  const gclAw =
    cookieGclAw ||
    deriveGclAw({ gclid: touch.gclid, timestamp: touch.ts, now });
  const fbp = cookieFbp;

  return {
    ...(fbc ? { fbc } : {}),
    ...(gclAw ? { gcl_aw: gclAw } : {}),
    ...(fbp ? { fbp } : {}),
  };
};
