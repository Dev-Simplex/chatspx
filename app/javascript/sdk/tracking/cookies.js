/**
 * Bloco 5.08 (T-C2.4) — leitura de cookies do site do cliente **por allowlist** (RC9).
 *
 * A regra é a mesma do `widget_tracking` do bloco 5.01: só sai daqui o que está numa lista
 * explícita. Varrer `document.cookie` e mandar tudo seria exfiltrar sessão, carrinho e o que
 * mais o cliente guardar — e o SDK roda no domínio dele, com acesso a tudo.
 *
 * `_ga_<ID>` é o único padrão, porque o nome carrega o measurement id (`_ga_ABC123`). O
 * casamento é ancorado (`^_ga_[A-Z0-9]+$`) para não pegar um `_ga_qualquer_coisa` do site.
 */

const EXACT = ['_fbp', '_fbc', '_ga', '_gcl_aw'];
const GA_SESSION = /^_ga_[A-Z0-9]+$/;

const isAllowed = name => EXACT.includes(name) || GA_SESSION.test(name);

/**
 * Os cookies permitidos, como objeto. Nunca lança: `document.cookie` pode estar bloqueado
 * por política do site.
 */
export const allowedCookies = (raw = window.document.cookie) => {
  try {
    return String(raw || '')
      .split(';')
      .reduce((acc, part) => {
        const separador = part.indexOf('=');
        if (separador < 1) return acc;

        const name = part.slice(0, separador).trim();
        if (isAllowed(name))
          acc[name] = decodeURIComponent(part.slice(separador + 1).trim());
        return acc;
      }, {});
  } catch {
    return {};
  }
};

/** O nome do cookie de sessão do GA4 desta propriedade: `G-ABC123` → `_ga_ABC123`. */
export const gaSessionCookieName = measurementId =>
  measurementId ? `_ga_${String(measurementId).replace(/^G-/, '')}` : null;
