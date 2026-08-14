import Auth from 'dashboard/api/auth';

/**
 * Copilot streaming transport — the ONLY place that knows the wire format.
 *
 * Contract C1 (owner: backend worker A1):
 *
 *   POST /api/v1/accounts/:account_id/captain/copilot_threads/:thread_id/stream
 *   Accept: text/event-stream
 *
 *   event: token   data: {"delta":"partial text"}
 *   event: done    data: {"message_id":123,"finish_reason":"stop"}
 *   event: error   data: {"code":"unauthorized","message":"..."}
 *
 * Cancelling is done by aborting the fetch, which closes the socket; the
 * server detects the disconnect and kills the job (also part of C1).
 *
 * `EventSource` is deliberately NOT used: it is GET-only and cannot carry the
 * devise-token-auth headers this API requires.
 */

/** Route suffix appended to the thread resource. Swap here if A1 renames it. */
export const COPILOT_STREAM_PATH = 'stream';

/** Turns the fake token emitter on: localStorage.chatspx_copilot_fake_stream = '1' */
export const FAKE_STREAM_STORAGE_KEY = 'chatspx_copilot_fake_stream';

/**
 * Reads the account id from the current dashboard URL, mirroring ApiClient.
 * @returns {string}
 */
export function accountIdFromRoute() {
  const path = window?.location?.pathname || '';
  if (!path.includes('/app/accounts')) return '';
  return path.split('/')[3] || '';
}

/**
 * @param {{ accountId?: string|number, threadId: string|number }} params
 * @returns {string}
 */
export function buildStreamUrl({ accountId, threadId }) {
  const account = accountId || accountIdFromRoute();
  return `/api/v1/accounts/${account}/captain/copilot_threads/${threadId}/${COPILOT_STREAM_PATH}`;
}

/**
 * devise-token-auth headers, same set `APIHelper` puts on axios.
 * Read at call time (not at import time) so a token refresh is picked up.
 * @returns {Object}
 */
export function authHeaders() {
  const fromAxios = window?.axios?.defaults?.headers?.common;
  if (fromAxios && fromAxios['access-token']) {
    const {
      'access-token': token,
      'token-type': type,
      client,
      expiry,
      uid,
    } = fromAxios;
    return { 'access-token': token, 'token-type': type, client, expiry, uid };
  }
  const data = Auth.getAuthData();
  if (!data) return {};
  return {
    'access-token': data['access-token'],
    'token-type': data['token-type'],
    client: data.client,
    expiry: data.expiry,
    uid: data.uid,
  };
}

/** Error carrying the HTTP status so callers can classify (401 vs 502 vs …). */
export class CopilotStreamHttpError extends Error {
  constructor(status, body) {
    super(`Copilot stream failed with HTTP ${status}`);
    this.name = 'CopilotStreamHttpError';
    this.status = status;
    this.body = body;
  }
}

/**
 * @returns {boolean} true when the local fake emitter should replace the network.
 */
export function isFakeStreamEnabled() {
  try {
    return window?.localStorage?.getItem(FAKE_STREAM_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

const FAKE_ANSWER = [
  'Olhando o histórico: o cliente está há 9 dias esperando o pedido e já deu um prazo.\n\n',
  'O rastreio mostra a encomenda parada desde 22/07 — não parece atraso de rota, e sim extravio.\n\n',
  'Sugiro abrir ocorrência na transportadora e oferecer o reenvio imediato, sem esperar a resposta dele.',
];

/**
 * Local token emitter used while the backend endpoint is unavailable (and by
 * the specs). Emits `token` frames on a timer so the panel renders text
 * progressively, then `done` — or `error` when `fakeError` is requested.
 *
 * @param {Object} params
 * @param {(event: {event: string, data: string}) => void} params.onEvent
 * @param {AbortSignal} [params.signal]
 * @param {number} [params.delayMs]
 * @param {string[]} [params.chunks]
 * @param {string} [params.fakeError]
 * @returns {Promise<void>}
 */
export function openFakeStream({
  onEvent,
  signal,
  delayMs = 45,
  chunks = FAKE_ANSWER,
  fakeError = null,
}) {
  return new Promise(resolve => {
    let index = 0;
    let timer = null;

    const stop = () => {
      if (timer) clearTimeout(timer);
      timer = null;
    };

    if (signal?.aborted) {
      resolve();
      return;
    }

    const onAbort = () => {
      stop();
      resolve();
    };
    signal?.addEventListener('abort', onAbort, { once: true });

    const tick = () => {
      if (signal?.aborted) return;
      if (fakeError) {
        onEvent({
          event: 'error',
          data: JSON.stringify({
            code: fakeError,
            message: 'fake stream error',
          }),
        });
        signal?.removeEventListener('abort', onAbort);
        resolve();
        return;
      }
      if (index >= chunks.length) {
        onEvent({
          event: 'done',
          data: JSON.stringify({ message_id: null, finish_reason: 'stop' }),
        });
        signal?.removeEventListener('abort', onAbort);
        resolve();
        return;
      }
      // Split each chunk into small deltas so the growth is visible.
      const chunk = chunks[index];
      index += 1;
      const words = chunk.split(/(\s+)/).filter(Boolean);
      words.forEach(word => {
        onEvent({ event: 'token', data: JSON.stringify({ delta: word }) });
      });
      timer = setTimeout(tick, delayMs);
    };

    timer = setTimeout(tick, delayMs);
  });
}

/**
 * Opens the real SSE connection and pumps raw chunks into `onChunk`.
 *
 * @param {Object} params
 * @param {string} params.url
 * @param {Object} params.body — JSON body (message, conversation_id, …)
 * @param {AbortSignal} params.signal
 * @param {string|null} [params.lastEventId] — sent as `Last-Event-ID` on retry
 * @param {(chunk: string) => void} params.onChunk
 * @returns {Promise<void>} resolves when the server closes the stream
 * @throws {CopilotStreamHttpError} when the response status is not 2xx
 */
export async function openHttpStream({
  url,
  body,
  signal,
  lastEventId = null,
  onChunk,
}) {
  const headers = {
    Accept: 'text/event-stream',
    'Content-Type': 'application/json',
    ...authHeaders(),
  };
  if (lastEventId) headers['Last-Event-ID'] = lastEventId;

  const response = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(body || {}),
    signal,
    credentials: 'same-origin',
    cache: 'no-store',
  });

  if (!response.ok) {
    let payload = null;
    try {
      payload = await response.text();
    } catch {
      payload = null;
    }
    throw new CopilotStreamHttpError(response.status, payload);
  }

  const body$ = response.body;
  if (!body$ || typeof body$.getReader !== 'function') {
    // No streaming body (very old browser or a mocked fetch): read it whole.
    const text = await response.text();
    onChunk(text);
    return;
  }

  const reader = body$.getReader();
  const decoder = new TextDecoder('utf-8');
  try {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      // eslint-disable-next-line no-await-in-loop
      const { value, done } = await reader.read();
      if (done) break;
      onChunk(decoder.decode(value, { stream: true }));
    }
    const tail = decoder.decode();
    if (tail) onChunk(tail);
  } finally {
    try {
      reader.releaseLock();
    } catch {
      /* reader already released by the abort */
    }
  }
}
