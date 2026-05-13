// Module-level reactive state (NOT inside <script setup>) so every caller
// shares the same locks Set. Without this, each instance of a `<script setup>`
// composable gets its own state and the gate would not work.
import { reactive, computed } from 'vue';

const LOCK_TTL_MS = 60_000;
const locks = reactive(new Map());
let sweeperTimer = null;

const isLockExpired = expiresAt => expiresAt && Date.now() > expiresAt;

const sweepExpiredLocks = () => {
  locks.forEach((expiresAt, key) => {
    if (isLockExpired(expiresAt)) locks.delete(key);
  });
};

const ensureSweeper = () => {
  if (sweeperTimer) return;
  sweeperTimer = setInterval(sweepExpiredLocks, LOCK_TTL_MS);
};

const canReload = computed(() => {
  sweepExpiredLocks();
  return locks.size === 0;
});

const acquire = (key, { ttl = LOCK_TTL_MS } = {}) => {
  ensureSweeper();
  locks.set(key, Date.now() + ttl);
};

const release = key => {
  locks.delete(key);
};

export function useReloadGate() {
  return {
    acquire,
    release,
    canReload,
  };
}

// Imperative helper for non-Vue contexts (router, action cable handlers).
export const canReloadNow = () => canReload.value;
