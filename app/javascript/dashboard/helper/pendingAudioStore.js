/* eslint-disable no-console */
// Pending audio recovery — persists recorded audio Blob in IndexedDB so it can
// be recovered after page reload / tab crash before the upload completes.
// Story P1.2 — frontend-audit §2.
import { openDB } from 'idb';
import * as Sentry from '@sentry/vue';

const DB_NAME = 'chatspx-pending-audio';
const STORE = 'pendingAudio';
const DB_VERSION = 1;
const TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

let dbPromise = null;

const getDb = () => {
  if (typeof indexedDB === 'undefined') return null;
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE)) {
          db.createObjectStore(STORE);
        }
      },
    }).catch(err => {
      Sentry.captureException(err, {
        tags: { feature: 'audio-recorder', step: 'idb-open' },
      });
      dbPromise = null;
      return null;
    });
  }
  return dbPromise;
};

const keyFor = conversationId => `pendingAudio:${conversationId}`;

export const savePendingAudio = async (conversationId, file) => {
  if (!conversationId || !file) return false;
  try {
    const db = await getDb();
    if (!db) return false;
    await db.put(
      STORE,
      {
        blob: file,
        name: file.name,
        mimeType: file.type,
        size: file.size,
        createdAt: Date.now(),
        conversationId,
      },
      keyFor(conversationId)
    );
    return true;
  } catch (err) {
    // Quota exceeded / private mode / etc. — primary path keeps working.
    Sentry.captureException(err, {
      tags: { feature: 'audio-recorder', step: 'idb-save' },
    });
    return false;
  }
};

export const getPendingAudio = async conversationId => {
  if (!conversationId) return null;
  try {
    const db = await getDb();
    if (!db) return null;
    const entry = await db.get(STORE, keyFor(conversationId));
    if (!entry) return null;

    // Drop stale entries (>7d).
    if (Date.now() - (entry.createdAt || 0) > TTL_MS) {
      await db.delete(STORE, keyFor(conversationId));
      return null;
    }
    return entry;
  } catch (err) {
    Sentry.captureException(err, {
      tags: { feature: 'audio-recorder', step: 'idb-read' },
    });
    return null;
  }
};

export const clearPendingAudio = async conversationId => {
  if (!conversationId) return;
  try {
    const db = await getDb();
    if (!db) return;
    await db.delete(STORE, keyFor(conversationId));
  } catch (err) {
    Sentry.captureException(err, {
      tags: { feature: 'audio-recorder', step: 'idb-delete' },
    });
  }
};
