import { onMounted, onUnmounted } from 'vue';
import {
  fetchVersion,
  forceCleanReload,
} from 'dashboard/helper/autoUpdateHelper';
import { useAlert } from 'dashboard/composables';

const POLL_INTERVAL = 300_000;
const IDLE_TIMEOUT = 30_000;
const UPDATED_FLAG = 'cw_just_updated';

export function useAutoUpdate() {
  const currentVersion = window.globalConfig?.APP_VERSION;
  if (!currentVersion) return;

  onMounted(() => {
    if (localStorage.getItem(UPDATED_FLAG)) {
      localStorage.removeItem(UPDATED_FLAG);
      useAlert('Sistema atualizado com sucesso! 🚀', {
        variant: 'success',
        icon: 'i-lucide-refresh-cw',
        duration: 5000,
      });
    }
  });

  let pollTimer = null;
  let idleTimer = null;
  let pendingUpdate = false;
  let lastActivity = Date.now();

  const onActivity = () => {
    lastActivity = Date.now();
    if (pendingUpdate) {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => forceCleanReload(), IDLE_TIMEOUT);
    }
  };

  const events = ['keydown', 'mousedown', 'touchstart'];
  events.forEach(e => document.addEventListener(e, onActivity, true));

  const checkVersion = async () => {
    const newVersion = await fetchVersion();
    if (!newVersion || newVersion === currentVersion) return;

    if (document.hidden || Date.now() - lastActivity >= IDLE_TIMEOUT) {
      forceCleanReload();
      return;
    }

    pendingUpdate = true;
    idleTimer = setTimeout(() => forceCleanReload(), IDLE_TIMEOUT);
  };

  pollTimer = setInterval(checkVersion, POLL_INTERVAL);

  onUnmounted(() => {
    clearInterval(pollTimer);
    clearTimeout(idleTimer);
    events.forEach(e => document.removeEventListener(e, onActivity, true));
  });
}
