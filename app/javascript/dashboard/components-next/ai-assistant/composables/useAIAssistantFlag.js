import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const SESSION_KEY = 'chatspx_ai_panel_v2_session';
const LOCAL_KEY = 'chatspx_ai_panel_v2';

/**
 * Reads a storage entry safely. Returns `null` if storage is unavailable
 * (private mode, quota exceeded, SSR, etc.) so callers can fall through.
 */
function safeRead(storageKey, key) {
  if (typeof window === 'undefined') return null;
  try {
    const storage = window[storageKey];
    if (!storage) return null;
    return storage.getItem(key);
  } catch {
    return null;
  }
}

/**
 * Reactive composable that resolves whether the AI Assistant v2 panel should
 * be shown to the current account.
 *
 * Resolution order (highest priority first):
 *   1. Server-side feature flag `ai_assistant_v2` as the rollout kill-switch.
 *   2. `sessionStorage.chatspx_ai_panel_v2_session === 'on'|'off'` (one-shot
 *      override set by `?aiv2=1` / `?aiv2=0` — see `applyAIAssistantQueryOverride`).
 *   3. `localStorage.chatspx_ai_panel_v2 === 'on'|'off'` (sticky per-browser
 *      override, useful for canary testing).
 *   4. Default: OFF.
 */
export function useAIAssistantFlag() {
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const currentAccountId = useMapGetter('getCurrentAccountId');

  return computed(() => {
    const accountId = currentAccountId.value;
    const serverEnabled = isFeatureEnabledonAccount.value(
      accountId,
      FEATURE_FLAGS.AI_ASSISTANT_V2
    );
    if (!serverEnabled) return false;

    const session = safeRead('sessionStorage', SESSION_KEY);
    if (session === 'on') return true;
    if (session === 'off') return false;

    const local = safeRead('localStorage', LOCAL_KEY);
    if (local === 'on') return true;
    if (local === 'off') return false;

    return true;
  });
}

/**
 * Applies a `?aiv2=1` / `?aiv2=0` query override to sessionStorage so the
 * `useAIAssistantFlag` resolver picks it up on next reads. Returns the value
 * applied (`'on'`, `'off'` or `null` if the param was absent/malformed).
 *
 * Call this once at app boot (e.g. inside the Dashboard root `mounted`).
 */
export function applyAIAssistantQueryOverride() {
  if (typeof window === 'undefined') return null;
  try {
    const params = new URLSearchParams(window.location.search);
    if (!params.has('aiv2')) return null;
    const raw = params.get('aiv2');
    let value = null;
    if (raw === '1' || raw === 'on' || raw === 'true') value = 'on';
    if (raw === '0' || raw === 'off' || raw === 'false') value = 'off';
    if (!value) return null;
    window.sessionStorage.setItem(SESSION_KEY, value);
    return value;
  } catch {
    return null;
  }
}

// Export keys for tests / debugging
export const AI_ASSISTANT_FLAG_KEYS = Object.freeze({
  SESSION_KEY,
  LOCAL_KEY,
});
