import { allowedCookies, gaSessionCookieName } from './cookies';

/**
 * Bloco 5.08 (T-C2.5) — `client_id` e `session_id` do GA4, **com timeout de 1 s**.
 *
 * POR QUE O TIMEOUT NÃO É DETALHE. `gtag('get', ID, 'client_id', cb)` devolve por CALLBACK,
 * e o callback **pode nunca ser chamado**: se o gtag da página ainda não terminou de
 * carregar, se o measurement id está errado, se um bloqueador comeu o script, o `gtag` vira
 * um empurrador de fila que ninguém drena. Sem prazo, a promessa fica pendente para sempre
 * e leva junto o passo que a espera — no nosso caso, a abertura da conversa.
 *
 * 1 s é o número do plano (T-C2.5) e é generoso: quando o gtag existe e responde, ele
 * responde em milissegundos.
 *
 * FALLBACK POR COOKIE, que é a implementação de referência do mercado:
 *   `_ga`        = `GA1.1.<client_id>`         → client_id são os DOIS últimos campos
 *   `_ga_<ID>`   = `GS1.1.<session_id>.<...>`  → session_id é o terceiro campo
 */

export const TIMEOUT_MS = 1000;

/** `GA1.1.1234567890.1690000000` → `1234567890.1690000000`. */
export const clientIdFromGaCookie = value => {
  const parts = String(value || '').split('.');
  return parts.length >= 4 ? parts.slice(-2).join('.') : null;
};

/** `GS1.1.1690000000.1.1.1690000060.0.0.0` → `1690000000`. */
export const sessionIdFromGaCookie = value => {
  const parts = String(value || '').split('.');
  return parts.length >= 3 ? parts[2] : null;
};

/**
 * Pergunta UM campo ao gtag, com prazo. Resolve com `null` — nunca rejeita — quando não há
 * gtag, quando ele lança, ou quando o prazo vence. Quem chama não precisa de `try`.
 */
const askGtag = (measurementId, field, timeoutMs) =>
  new Promise(resolve => {
    const { gtag } = window;
    if (typeof gtag !== 'function' || !measurementId) {
      resolve(null);
      return;
    }

    let done = false;
    const finish = value => {
      if (done) return;
      done = true;
      resolve(value ?? null);
    };

    const timer = setTimeout(() => finish(null), timeoutMs);

    try {
      gtag('get', measurementId, field, value => {
        clearTimeout(timer);
        finish(value);
      });
    } catch {
      clearTimeout(timer);
      finish(null);
    }
  });

/**
 * `{ client_id, session_id }` do GA4 — do gtag quando ele responde a tempo, do cookie
 * quando não. Chaves ausentes quando nenhum caminho deu resposta: mandar `null` ao backend
 * gravaria "não sei" como se fosse valor.
 */
export const googleIds = async ({
  measurementId,
  timeoutMs = TIMEOUT_MS,
  cookies = allowedCookies(),
} = {}) => {
  const [clientId, sessionId] = await Promise.all([
    askGtag(measurementId, 'client_id', timeoutMs),
    askGtag(measurementId, 'session_id', timeoutMs),
  ]);

  const { _ga: gaCookie } = cookies;
  const sessionCookie = cookies[gaSessionCookieName(measurementId)];

  const resolvedClient = clientId || clientIdFromGaCookie(gaCookie);
  const resolvedSession = sessionId || sessionIdFromGaCookie(sessionCookie);

  return {
    ...(resolvedClient ? { ga_client_id: resolvedClient } : {}),
    ...(resolvedSession ? { ga_session_id: String(resolvedSession) } : {}),
  };
};
