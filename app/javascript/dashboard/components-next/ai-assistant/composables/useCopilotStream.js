import { computed, ref, onBeforeUnmount } from 'vue';
import {
  buildStreamUrl,
  authHeaders,
  openHttpStream,
  openFakeStream,
  isFakeStreamEnabled,
  CopilotStreamHttpError,
} from 'dashboard/api/captain/copilotStream';
import { createSSEParser, parseEventData } from './sseParser';

/**
 * Copilot SSE client.
 *
 * Responsibilities kept here (and nowhere else in the panel):
 *   - open/close the stream and expose the text as it grows;
 *   - preserve token order (single HTTP response = ordered byte stream);
 *   - real cancellation — `stop()` aborts the fetch, which closes the socket
 *     and, per contract C1, kills the job server-side. It is not a UI-only
 *     "hide the spinner";
 *   - sensible reconnection — network drops retry with backoff, HTTP errors
 *     (401/403/429/5xx) do NOT, because retrying them just burns time;
 *   - a watchdog so a silent server can never leave a spinner running forever.
 */

/** Terminal states returned by `start()`. */
export const STREAM_STATUS = Object.freeze({
  DONE: 'done',
  CANCELLED: 'cancelled',
  ERROR: 'error',
});

/** Error codes this client produces (backend codes pass through untouched). */
export const STREAM_ERROR_CODES = Object.freeze({
  UNAUTHORIZED: 'unauthorized',
  RATE_LIMIT: 'rate_limit',
  CAPTAIN_UNSTABLE: 'captain_unstable',
  TIMEOUT: 'timeout',
  NETWORK: 'network',
  EMPTY_RESPONSE: 'empty_response',
  UNKNOWN: 'unknown',
});

/** No frame at all for this long => the stream is dead, stop waiting. */
export const STREAM_IDLE_TIMEOUT_MS = 30_000;
const MAX_RECONNECT_ATTEMPTS = 2;
const RECONNECT_BACKOFF_MS = [800, 2000];

/**
 * Maps an HTTP status to a UI error code.
 * @param {number} status
 * @returns {string}
 */
export function codeForHttpStatus(status) {
  if (status === 401 || status === 403) return STREAM_ERROR_CODES.UNAUTHORIZED;
  if (status === 429) return STREAM_ERROR_CODES.RATE_LIMIT;
  if (status === 502 || status === 503) {
    return STREAM_ERROR_CODES.CAPTAIN_UNSTABLE;
  }
  if (status === 504) return STREAM_ERROR_CODES.TIMEOUT;
  return STREAM_ERROR_CODES.UNKNOWN;
}

const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export function useCopilotStream() {
  const isStreaming = ref(false);
  const streamedText = ref('');
  const streamError = ref(null); // { code, message }

  let controller = null;
  let cancelledByUser = false;
  let idleTimer = null;
  // Guarda de quem é o stream em curso, para o cancelamento saber o que avisar
  // ao servidor. Preenchido no start(), limpo quando a geração termina.
  let activeStream = {};

  const canStop = computed(() => isStreaming.value);

  function clearIdleTimer() {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
  }

  /**
   * Avisa o servidor, por fora da conexão, que esta geração foi cancelada.
   *
   * Abortar o fetch sozinho TAMBÉM cancela, mas a detecção depende do buffer do
   * socket encher — e tokens são pequenos. Medido contra a OpenAI real: o
   * servidor seguiu gerando ~4s depois de o agente sair, queimando token do
   * cliente. O DELETE grava um sinal que a geração consulta a cada ~200ms.
   *
   * É "melhor esforço": se falhar, o abort ainda cancela, só que mais devagar.
   * Por isso nunca levanta.
   */
  function signalServerCancel({ accountId, threadId }) {
    if (!threadId) return;
    try {
      const url = buildStreamUrl({ accountId, threadId });
      const headers = { ...authHeaders(), 'Content-Type': 'application/json' };
      // keepalive: o cancelamento precisa sair mesmo se a aba estiver fechando.
      fetch(url, { method: 'DELETE', headers, keepalive: true }).catch(
        () => {}
      );
    } catch {
      // nada a fazer: o abort abaixo continua valendo
    }
  }

  /**
   * Aborta o stream em curso. Faz as duas coisas, não uma ou outra:
   * fecha o socket (para de receber) e avisa o servidor (para de gerar).
   * @param {string} [reason]
   */
  function stop(reason = 'user') {
    if (!controller) return;
    cancelledByUser = reason !== 'error';
    clearIdleTimer();
    signalServerCancel(activeStream);
    controller.abort(
      new DOMException('Copilot stream cancelled', 'AbortError')
    );
    controller = null;
  }

  /**
   * Runs one connection attempt and feeds the parsed frames to the handlers.
   *
   * @returns {Promise<{terminal: string|null, messageId: any, finishReason: string|null, error: Object|null, sawToken: boolean, lastEventId: string|null}>}
   */
  async function runAttempt({
    url,
    body,
    signal,
    lastEventId,
    onToken,
    useFake,
  }) {
    const result = {
      terminal: null,
      messageId: null,
      finishReason: null,
      error: null,
      sawToken: false,
      lastEventId,
      thrown: null,
    };

    const armIdleWatchdog = () => {
      clearIdleTimer();
      idleTimer = setTimeout(() => {
        result.error = { code: STREAM_ERROR_CODES.TIMEOUT, message: '' };
        result.terminal = STREAM_STATUS.ERROR;
        // Abort with `error` so the caller does not treat it as a user cancel.
        stop('error');
      }, STREAM_IDLE_TIMEOUT_MS);
    };

    const handleEvent = frame => {
      armIdleWatchdog();
      // Dedup on reconnect: a server that numbers its frames may replay the
      // ones we already rendered. Numeric ids we have seen are dropped.
      if (frame.id != null && frame.id !== '') {
        const incoming = Number(frame.id);
        const seen = Number(result.lastEventId);
        if (
          Number.isFinite(incoming) &&
          Number.isFinite(seen) &&
          incoming <= seen
        ) {
          return;
        }
        result.lastEventId = frame.id;
      }

      const payload = parseEventData(frame.data);

      if (frame.event === 'token') {
        const delta = payload?.delta;
        if (typeof delta === 'string' && delta.length) {
          result.sawToken = true;
          streamedText.value += delta;
          if (typeof onToken === 'function') onToken(delta);
        }
        return;
      }
      if (frame.event === 'done') {
        result.messageId = payload?.message_id ?? null;
        result.finishReason = payload?.finish_reason || 'stop';
        result.terminal = STREAM_STATUS.DONE;
        return;
      }
      if (frame.event === 'error') {
        result.error = {
          code: payload?.code || STREAM_ERROR_CODES.UNKNOWN,
          message: payload?.message || '',
        };
        result.terminal = STREAM_STATUS.ERROR;
      }
    };

    const parser = createSSEParser(handleEvent);
    armIdleWatchdog();

    try {
      if (useFake) {
        await openFakeStream({ signal, onEvent: handleEvent });
      } else {
        await openHttpStream({
          url,
          body,
          signal,
          lastEventId: result.lastEventId,
          onChunk: chunk => parser.push(chunk),
        });
        parser.flush();
      }
    } catch (error) {
      // Never propagate: the caller needs `lastEventId` and the partial text
      // from this attempt to decide whether a retry can resume or must reset.
      result.thrown = error;
    } finally {
      clearIdleTimer();
    }

    return result;
  }

  /**
   * Starts a streamed answer.
   *
   * @param {Object} params
   * @param {string|number} params.threadId
   * @param {string|number} [params.accountId]
   * @param {string} params.message — the agent's question
   * @param {string|number} [params.conversationId]
   * @param {(delta: string) => void} [params.onToken]
   * @returns {Promise<{status: string, text: string, messageId: any, finishReason: string|null, error: Object|null}>}
   */
  async function start({
    threadId,
    accountId,
    message,
    conversationId,
    onToken,
  } = {}) {
    stop('restart');
    cancelledByUser = false;
    streamError.value = null;
    streamedText.value = '';
    isStreaming.value = true;
    activeStream = { accountId, threadId };

    const useFake = isFakeStreamEnabled();
    const url = buildStreamUrl({ accountId, threadId });
    const body = { message, conversation_id: conversationId };

    let attempt = 0;
    let lastEventId = null;

    try {
      // eslint-disable-next-line no-constant-condition
      while (true) {
        controller = new AbortController();
        const { signal } = controller;

        // eslint-disable-next-line no-await-in-loop
        const outcome = await runAttempt({
          url,
          body,
          signal,
          lastEventId,
          onToken,
          useFake,
        });
        const thrown = outcome.thrown;

        const aborted = signal.aborted;
        controller = null;

        if (outcome?.terminal === STREAM_STATUS.DONE) {
          return {
            status: STREAM_STATUS.DONE,
            text: streamedText.value,
            messageId: outcome.messageId,
            finishReason: outcome.finishReason,
            error: null,
          };
        }

        if (outcome?.terminal === STREAM_STATUS.ERROR && outcome.error) {
          streamError.value = outcome.error;
          return {
            status: STREAM_STATUS.ERROR,
            text: streamedText.value,
            messageId: null,
            finishReason: 'error',
            error: outcome.error,
          };
        }

        if (aborted && cancelledByUser) {
          return {
            status: STREAM_STATUS.CANCELLED,
            text: streamedText.value,
            messageId: null,
            finishReason: 'cancelled',
            error: null,
          };
        }

        // HTTP-level failure: never retried — a 401 stays a 401.
        if (thrown instanceof CopilotStreamHttpError) {
          const failure = {
            code: codeForHttpStatus(thrown.status),
            message: '',
            status: thrown.status,
          };
          streamError.value = failure;
          return {
            status: STREAM_STATUS.ERROR,
            text: streamedText.value,
            messageId: null,
            finishReason: 'error',
            error: failure,
          };
        }

        // Everything else (dropped socket, DNS blip, stream closed before
        // `done`) is retried with backoff.
        if (attempt < MAX_RECONNECT_ATTEMPTS) {
          lastEventId = outcome?.lastEventId ?? lastEventId;
          if (!lastEventId) {
            // Server does not number frames: assume the retry replays the
            // whole answer, so drop what we rendered to avoid duplicates.
            streamedText.value = '';
          }
          // eslint-disable-next-line no-await-in-loop
          await sleep(RECONNECT_BACKOFF_MS[attempt] || 2000);
          attempt += 1;
          // eslint-disable-next-line no-continue
          continue;
        }

        const failure = {
          code: STREAM_ERROR_CODES.NETWORK,
          message: thrown?.message || '',
        };
        streamError.value = failure;
        return {
          status: STREAM_STATUS.ERROR,
          text: streamedText.value,
          messageId: null,
          finishReason: 'error',
          error: failure,
        };
      }
    } finally {
      clearIdleTimer();
      isStreaming.value = false;
      controller = null;
    }
  }

  onBeforeUnmount(() => stop('unmount'));

  return {
    isStreaming,
    streamedText,
    streamError,
    canStop,
    start,
    stop,
  };
}
