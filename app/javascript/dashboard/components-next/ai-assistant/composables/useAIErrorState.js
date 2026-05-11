import { ref, onBeforeUnmount } from 'vue';

/**
 * Reactive AI error classifier + cooldown driver for the Copilot panel.
 *
 * Maps known network/HTTP signals to a small set of UI states each rendered
 * differently by `AIErrorBanner.vue`:
 *
 *   - `rate_limit`        429 — drives a countdown from `Retry-After`.
 *   - `captain_unstable`  502/503 — Captain transient outage.
 *   - `timeout`           ECONNABORTED or client-side >10s.
 *   - `empty_response`    HTTP 200 with empty/null body.
 *   - `network`           ERR_NETWORK / offline.
 *   - `aborted`           User/context cancelled — silenced in the UI.
 *
 * Anything else is classified as `null` (unknown) so the caller can decide.
 */
export function useAIErrorState() {
  const errorType = ref(null);
  const retryAfterSeconds = ref(0);
  let cooldownInterval = null;

  function clearCooldown() {
    if (cooldownInterval) {
      clearInterval(cooldownInterval);
      cooldownInterval = null;
    }
  }

  function startCooldown() {
    clearCooldown();
    cooldownInterval = setInterval(() => {
      if (retryAfterSeconds.value > 0) {
        retryAfterSeconds.value -= 1;
      } else {
        clearCooldown();
      }
    }, 1000);
  }

  function classify(error) {
    if (!error) return null;
    if (error.name === 'AbortError' || error.name === 'CanceledError') {
      return 'aborted';
    }
    if (error.code === 'ERR_NETWORK') return 'network';
    if (error.code === 'ECONNABORTED') return 'timeout';
    const status = error?.response?.status;
    if (status === 429) {
      const headerValue = error.response?.headers?.['retry-after'];
      const parsed = parseInt(headerValue ?? '60', 10);
      retryAfterSeconds.value =
        Number.isFinite(parsed) && parsed > 0 ? parsed : 60;
      startCooldown();
      return 'rate_limit';
    }
    if (status === 502 || status === 503) return 'captain_unstable';
    if (status === 504) return 'timeout';
    return null;
  }

  function handle(error) {
    errorType.value = classify(error);
    return errorType.value;
  }

  function setEmpty() {
    errorType.value = 'empty_response';
  }

  function setTimeout() {
    errorType.value = 'timeout';
  }

  function clear() {
    errorType.value = null;
    retryAfterSeconds.value = 0;
    clearCooldown();
  }

  onBeforeUnmount(clearCooldown);

  return {
    errorType,
    retryAfterSeconds,
    classify,
    handle,
    setEmpty,
    setTimeout,
    clear,
  };
}
