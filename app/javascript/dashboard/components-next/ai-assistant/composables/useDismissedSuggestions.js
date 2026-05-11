/**
 * Persistent per-conversation dismissal store for the Copilot smart banner.
 *
 * Backed by `localStorage` under a single key, with:
 *   - 7-day TTL per entry (keeps storage small and avoids stale dismissals
 *     when the customer actually comes back to the conversation later)
 *   - 200-entry hard cap (LRU by last-write timestamp) so a noisy account
 *     never spams the storage quota
 *   - Defensive read/write that swallows JSON parse errors and quota
 *     exceeded exceptions — the banner falls back to "show" behaviour rather
 *     than crashing the panel.
 *
 * Storage shape:
 *   {
 *     v: 1,
 *     items: {
 *       [conversationId]: {
 *         ids: ['waiting', 'long_thread', ...], // dismissed suggestion ids
 *         ts: 1714600000000                      // last write epoch (ms)
 *       }
 *     }
 *   }
 */

const STORAGE_KEY = 'chatspx_dismissed_suggestions';
const TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const MAX_ENTRIES = 200;

function safeStorage() {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage || null;
  } catch {
    return null;
  }
}

function read() {
  const storage = safeStorage();
  if (!storage) return { v: 1, items: {} };
  try {
    const raw = JSON.parse(
      storage.getItem(STORAGE_KEY) || '{"v":1,"items":{}}'
    );
    const items = raw.items || {};
    const now = Date.now();
    const filtered = {};
    Object.entries(items).forEach(([key, value]) => {
      if (value && typeof value.ts === 'number' && now - value.ts < TTL_MS) {
        filtered[key] = value;
      }
    });
    return { v: 1, items: filtered };
  } catch {
    return { v: 1, items: {} };
  }
}

function write(data) {
  const storage = safeStorage();
  if (!storage) return;
  try {
    let payload = data;
    const entries = Object.entries(payload.items || {});
    if (entries.length > MAX_ENTRIES) {
      const trimmed = entries
        .sort((a, b) => (b[1]?.ts ?? 0) - (a[1]?.ts ?? 0))
        .slice(0, MAX_ENTRIES);
      payload = { v: 1, items: Object.fromEntries(trimmed) };
    }
    storage.setItem(STORAGE_KEY, JSON.stringify(payload));
  } catch {
    /* quota exceeded / serialization error — silent */
  }
}

export function useDismissedSuggestions() {
  function isDismissed(conversationId, suggestionId) {
    if (!conversationId) return false;
    const data = read();
    const entry = data.items[conversationId];
    if (!entry) return false;
    const ids = entry.ids || [];
    if (suggestionId) return ids.includes(suggestionId);
    return ids.length > 0;
  }

  function add(conversationId, suggestionId) {
    if (!conversationId || !suggestionId) return;
    const data = read();
    const entry = data.items[conversationId] || { ids: [], ts: Date.now() };
    if (!entry.ids.includes(suggestionId)) {
      entry.ids = [...entry.ids, suggestionId];
    }
    entry.ts = Date.now();
    data.items[conversationId] = entry;
    write(data);
  }

  function clear(conversationId) {
    const data = read();
    if (conversationId) {
      delete data.items[conversationId];
    }
    write(data);
  }

  return { isDismissed, add, clear };
}

// Exported for tests / debugging
export const DISMISSED_SUGGESTIONS_KEYS = Object.freeze({
  STORAGE_KEY,
  TTL_MS,
  MAX_ENTRIES,
});
