import { computed, ref } from 'vue';
import CopilotThreadsAPI from 'dashboard/api/captain/copilotThreads';
import CopilotMessagesAPI from 'dashboard/api/captain/copilotMessages';
import { accountIdFromRoute } from 'dashboard/api/captain/copilotStream';

/**
 * Thread + history for the Copilot panel.
 *
 * `copilot_threads` has no `conversation_id` column (db/schema.rb) and this
 * round is not allowed to add a migration, so the conversation → thread link
 * lives on the client: a small map in localStorage, scoped per account. It
 * survives a reload and a conversation switch, which is exactly what the
 * requirement asks for ("keep the history when leaving and coming back").
 * The day the backend owns the link, `resolveThreadId` is the only function
 * that changes.
 *
 * The in-memory cache keeps the panel instant when the agent bounces between
 * two conversations; the API is only hit on a cold read.
 */

const STORAGE_KEY = 'chatspx_copilot_thread_map';

/** conversationId -> { threadId, messages } for this page session. */
const memoryCache = new Map();

function readMap() {
  try {
    const raw = window?.localStorage?.getItem(STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function writeMap(map) {
  try {
    window?.localStorage?.setItem(STORAGE_KEY, JSON.stringify(map));
  } catch {
    /* private mode / quota — the in-memory cache still works */
  }
}

/**
 * @param {string|number} conversationId
 * @returns {number|null}
 */
export function getStoredThreadId(conversationId) {
  if (!conversationId) return null;
  const account = accountIdFromRoute() || 'default';
  const stored = readMap()?.[account]?.[String(conversationId)];
  return stored ? Number(stored) : null;
}

/**
 * @param {string|number} conversationId
 * @param {number} threadId
 */
export function storeThreadId(conversationId, threadId) {
  if (!conversationId || !threadId) return;
  const account = accountIdFromRoute() || 'default';
  const map = readMap();
  map[account] = {
    ...(map[account] || {}),
    [String(conversationId)]: threadId,
  };
  writeMap(map);
}

/**
 * @param {string|number} conversationId
 */
export function forgetThreadId(conversationId) {
  const account = accountIdFromRoute() || 'default';
  const map = readMap();
  if (map[account]) {
    delete map[account][String(conversationId)];
    writeMap(map);
  }
  memoryCache.delete(String(conversationId));
}

/**
 * Normalizes a persisted `copilot_messages` record into the panel shape.
 * @param {Object} record
 * @returns {{id: number, type: string, text: string, createdAt: number}|null}
 */
export function normalizeMessage(record) {
  if (!record) return null;
  const type = record.message_type === 'user' ? 'user' : 'assistant';
  const text =
    typeof record.message === 'string'
      ? record.message
      : record.message?.content || '';
  if (record.message_type === 'assistant_thinking') return null;
  return {
    id: record.id,
    type,
    text,
    createdAt: record.created_at,
    persisted: true,
  };
}

export function useCopilotThread() {
  const threadId = ref(null);
  const messages = ref([]);
  const isLoadingThread = ref(false);
  const loadError = ref(null);

  // "Loading" and "empty" are different screens — never collapse them.
  const isEmpty = computed(
    () => !isLoadingThread.value && messages.value.length === 0
  );

  /**
   * Loads the thread bound to a conversation. Memory cache first, then the
   * stored id, then the API.
   * @param {string|number} conversationId
   * @returns {Promise<void>}
   */
  async function loadForConversation(conversationId) {
    loadError.value = null;
    const key = String(conversationId || '');

    if (memoryCache.has(key)) {
      const cached = memoryCache.get(key);
      threadId.value = cached.threadId;
      messages.value = [...cached.messages];
      isLoadingThread.value = false;
      return;
    }

    const stored = getStoredThreadId(conversationId);
    if (!stored) {
      threadId.value = null;
      messages.value = [];
      isLoadingThread.value = false;
      return;
    }

    threadId.value = stored;
    isLoadingThread.value = true;
    try {
      const { data } = await CopilotMessagesAPI.get(stored);
      const payload = Array.isArray(data) ? data : data?.payload || [];
      messages.value = payload.map(normalizeMessage).filter(Boolean);
      memoryCache.set(key, {
        threadId: stored,
        messages: [...messages.value],
      });
    } catch (error) {
      // A thread deleted server-side must not wedge the panel on a spinner.
      const status = error?.response?.status;
      if (status === 404) {
        forgetThreadId(conversationId);
        threadId.value = null;
        messages.value = [];
      } else {
        loadError.value = error;
      }
    } finally {
      isLoadingThread.value = false;
    }
  }

  /**
   * Returns the thread id for this conversation, creating it on first use.
   *
   * `skip_response: true` asks the backend NOT to enqueue the legacy
   * (non-streaming) response job — the streaming endpoint answers instead.
   * Today's controller ignores unknown params, so this is forward-compatible.
   *
   * @param {Object} params
   * @param {string|number} params.conversationId
   * @param {string|number} params.assistantId
   * @param {string} params.message — used as the thread title
   * @returns {Promise<number|null>}
   */
  async function ensureThread({ conversationId, assistantId, message }) {
    if (threadId.value) return threadId.value;

    const { data } = await CopilotThreadsAPI.create({
      message,
      assistant_id: assistantId,
      conversation_id: conversationId,
      skip_response: true,
    });
    const created = data?.id || data?.payload?.id || null;
    if (created) {
      threadId.value = created;
      storeThreadId(conversationId, created);
    }
    return created;
  }

  function syncCache(conversationId) {
    const key = String(conversationId || '');
    if (!key) return;
    memoryCache.set(key, {
      threadId: threadId.value,
      messages: [...messages.value],
    });
  }

  /** Appends a message to the thread and keeps the cache in sync. */
  function appendMessage(conversationId, message) {
    messages.value = [...messages.value, message];
    syncCache(conversationId);
  }

  /** Replaces a message in place (used while streaming tokens in). */
  function updateMessage(conversationId, id, patch) {
    messages.value = messages.value.map(item =>
      item.id === id ? { ...item, ...patch } : item
    );
    syncCache(conversationId);
  }

  /** Drops a message (cancelled generation, edited question, …). */
  function removeMessage(conversationId, id) {
    messages.value = messages.value.filter(item => item.id !== id);
    syncCache(conversationId);
  }

  /** Drops everything from `id` onwards — used by edit/regenerate. */
  function truncateFrom(conversationId, id) {
    const index = messages.value.findIndex(item => item.id === id);
    if (index === -1) return;
    messages.value = messages.value.slice(0, index);
    syncCache(conversationId);
  }

  /** Starts a brand new thread for this conversation. */
  function reset(conversationId) {
    threadId.value = null;
    messages.value = [];
    loadError.value = null;
    if (conversationId) forgetThreadId(conversationId);
  }

  return {
    threadId,
    messages,
    isLoadingThread,
    isEmpty,
    loadError,
    loadForConversation,
    ensureThread,
    appendMessage,
    updateMessage,
    removeMessage,
    truncateFrom,
    reset,
  };
}

/** Test helper — clears the module-level cache between specs. */
export function clearThreadCache() {
  memoryCache.clear();
}
