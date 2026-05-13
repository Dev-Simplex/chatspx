import { canReloadNow } from 'dashboard/composables/useReloadGate';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

let initialVersion = null;
let pendingReloadCheck = null;

export function setInitialVersion(version) {
  initialVersion = version;
}

export function getInitialVersion() {
  return initialVersion;
}

export async function fetchVersion() {
  try {
    const response = await fetch(`/version.json?t=${Date.now()}`);
    const { version } = await response.json();
    return version;
  } catch {
    return null;
  }
}

// Keys that must survive a `forceCleanReload`. Drafts (Vuex `draftMessages`
// module persists to `LOCAL_STORAGE_KEYS.DRAFT_MESSAGES`) used to be wiped on
// every auto-update, which is what made operators "lose what they were typing"
// after a silent reload. Reply-to context and recent searches are equally
// session-local UX state that should not be destroyed.
const PRESERVE_PATTERNS = [
  'token',
  'user_id',
  'cw_d_',
  'cw_just_updated',
  LOCAL_STORAGE_KEYS.DRAFT_MESSAGES,
  LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO,
  LOCAL_STORAGE_KEYS.COLOR_SCHEME,
  LOCAL_STORAGE_KEYS.RECENT_SEARCHES,
];

const shouldPreserveKey = key =>
  PRESERVE_PATTERNS.some(pattern => key.includes(pattern));

export function forceCleanReload() {
  if (navigator.serviceWorker) {
    navigator.serviceWorker.getRegistrations().then(registrations => {
      registrations.forEach(r => r.unregister());
    });
  }

  if (window.caches) {
    caches.keys().then(keys => {
      keys.forEach(key => caches.delete(key));
    });
  }

  const keysToRemove = [];
  for (let i = 0; i < localStorage.length; i += 1) {
    const key = localStorage.key(i);
    if (!shouldPreserveKey(key)) {
      keysToRemove.push(key);
    }
  }
  keysToRemove.forEach(key => localStorage.removeItem(key));

  sessionStorage.clear();

  localStorage.setItem('cw_just_updated', 'true');
  window.location.reload(true);
}

// Gate-aware reload. If a critical operation (audio recording, upload,
// in-progress message composition) holds a lock in `useReloadGate`, we
// retry every 2s — never force-interrupt the operator.
export function reloadWhenSafe({ onWait } = {}) {
  if (canReloadNow()) {
    forceCleanReload();
    return;
  }
  if (typeof onWait === 'function') onWait();
  if (pendingReloadCheck) return;
  pendingReloadCheck = setInterval(() => {
    if (canReloadNow()) {
      clearInterval(pendingReloadCheck);
      pendingReloadCheck = null;
      forceCleanReload();
    }
  }, 2_000);
}
