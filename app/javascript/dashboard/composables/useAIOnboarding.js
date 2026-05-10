import { ref, onBeforeUnmount } from 'vue';

/**
 * Persistent flag for the ChatSPX Copilot first-time coachmark.
 *
 * Uses `localStorage.chatspx_ai_onboarded` and reacts to changes in other
 * tabs via the `storage` event so the pulse + coachmark disappear in
 * sync across windows.
 *
 * Stored values:
 *  - 'true'  → user explicitly confirmed (clicked "Quero conhecer")
 *  - 'auto'  → coachmark auto-dismissed after 8s (also counts as onboarded)
 *  - missing → not onboarded yet, show pulse + coachmark
 */
const STORAGE_KEY = 'chatspx_ai_onboarded';

function readFlag() {
  try {
    if (typeof window === 'undefined') return false;
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw === 'true' || raw === 'auto';
  } catch (e) {
    // localStorage corrupted, disabled or quota exceeded → treat as not onboarded
    return false;
  }
}

export function useAIOnboarding() {
  const isOnboarded = ref(readFlag());
  const shouldShowOnboarding = ref(!isOnboarded.value);

  function syncFromStorage() {
    const flag = readFlag();
    isOnboarded.value = flag;
    shouldShowOnboarding.value = !flag;
  }

  function markOnboarded(method = 'confirm') {
    try {
      if (typeof window !== 'undefined') {
        const value = method === 'auto' ? 'auto' : 'true';
        window.localStorage.setItem(STORAGE_KEY, value);
      }
    } catch (e) {
      // quota exceeded / disabled — fail silently, still flip the local state
    }
    isOnboarded.value = true;
    shouldShowOnboarding.value = false;
  }

  function reset() {
    try {
      if (typeof window !== 'undefined') {
        window.localStorage.removeItem(STORAGE_KEY);
      }
    } catch (e) {
      // ignore
    }
    isOnboarded.value = false;
    shouldShowOnboarding.value = true;
  }

  function handleStorageChange(event) {
    if (event.key === STORAGE_KEY) syncFromStorage();
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('storage', handleStorageChange);
  }

  onBeforeUnmount(() => {
    if (typeof window !== 'undefined') {
      window.removeEventListener('storage', handleStorageChange);
    }
  });

  return {
    isOnboarded,
    shouldShowOnboarding,
    markOnboarded,
    reset,
  };
}
