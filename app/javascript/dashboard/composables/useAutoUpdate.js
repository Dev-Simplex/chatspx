import { onMounted, onUnmounted, ref } from 'vue';
import {
  fetchVersion,
  setInitialVersion,
} from 'dashboard/helper/autoUpdateHelper';
import { useAlert } from 'dashboard/composables';

const POLL_INTERVAL = 300_000;
const UPDATED_FLAG = 'cw_just_updated';

// Module-level reactive flag: any consumer (toast banner, dev tools) can
// observe `pendingUpdate` and react. We do not force a reload here — the
// operator decides when via the toast button.
const pendingUpdate = ref(false);

export function usePendingUpdate() {
  return pendingUpdate;
}

export function useAutoUpdate() {
  let currentVersion = null;
  let pollTimer = null;

  const checkVersion = async () => {
    const newVersion = await fetchVersion();
    if (!newVersion) return;

    if (!currentVersion) {
      currentVersion = newVersion;
      setInitialVersion(newVersion);
      return;
    }

    if (newVersion === currentVersion) return;

    pendingUpdate.value = true;
  };

  onMounted(() => {
    if (localStorage.getItem(UPDATED_FLAG)) {
      localStorage.removeItem(UPDATED_FLAG);
      useAlert('Sistema atualizado com sucesso! 🚀', {
        variant: 'success',
        icon: 'i-lucide-refresh-cw',
        duration: 5000,
      });
    }

    checkVersion();
    pollTimer = setInterval(checkVersion, POLL_INTERVAL);
  });

  onUnmounted(() => {
    clearInterval(pollTimer);
  });
}
