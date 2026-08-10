<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';
import { LocalStorage } from 'shared/helpers/localStorage';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const { accountId } = useAccount();
// A policy de waha_connections exige administrador: sem esse guard todo agente
// logado dispara um 401 a cada ciclo de polling (engolido pelo catch de loadConnections).
const { isAdmin } = useAdmin();

const connections = ref([]);
const pollingInterval = ref(null);
const userDismissedBanner = ref(false);
const isLoading = ref(false);

// MISSING = a inbox aponta para uma sessão que não existe mais no WAHA. Antes
// esse caso sumia da lista (ela era montada a partir das sessões), então o pior
// estado possível era o único sem alerta.
const PROBLEMATIC_STATUSES = ['STOPPED', 'FAILED', 'SCAN_QR_CODE', 'MISSING'];
const POLLING_INTERVAL = 90000; // 90 segundos
const DISMISS_STORAGE_KEY = 'wahaConnectionsBannerDismissed';

const isValidAccountId = value => {
  return value && !Number.isNaN(Number(value)) && value > 0;
};

const getStatusText = status => {
  const statusMap = {
    STOPPED: t('GENERAL_SETTINGS.WAHA_BANNER.STATUS_STOPPED'),
    FAILED: t('GENERAL_SETTINGS.WAHA_BANNER.STATUS_FAILED'),
    SCAN_QR_CODE: t('GENERAL_SETTINGS.WAHA_BANNER.STATUS_SCAN_QR'),
    MISSING: t('GENERAL_SETTINGS.WAHA_BANNER.STATUS_MISSING'),
  };
  return statusMap[status] || status;
};

const problematicConnections = computed(() => {
  return connections.value.filter(connection =>
    PROBLEMATIC_STATUSES.includes(connection.status)
  );
});

const hasProblematicConnections = computed(() => {
  return problematicConnections.value.length > 0;
});

const shouldShowBanner = computed(() => {
  return (
    isAdmin.value &&
    hasProblematicConnections.value &&
    !userDismissedBanner.value &&
    isValidAccountId(accountId.value)
  );
});

const shouldPollOnCurrentRoute = computed(() => {
  const currentPath = route?.path || '';
  // Avoid constant background polling while user is in Kanban.
  return !currentPath.includes('/kanban');
});

const bannerMessage = computed(() => {
  const count = problematicConnections.value.length;
  if (count === 1 && problematicConnections.value[0]) {
    const connection = problematicConnections.value[0];
    const statusText = getStatusText(connection?.status);
    return t('GENERAL_SETTINGS.WAHA_BANNER.SINGLE_CONNECTION_ISSUE', {
      inbox: connection?.inbox_name || connection?.session_name || '',
      status: statusText.toLowerCase(),
    });
  }
  return t('GENERAL_SETTINGS.WAHA_BANNER.MULTIPLE_CONNECTIONS_ISSUE', {
    count,
  });
});

const checkDismissedState = () => {
  try {
    const dismissed = LocalStorage.get(DISMISS_STORAGE_KEY);
    if (dismissed) {
      userDismissedBanner.value = true;
    }
  } catch {
    // If localStorage access fails, continue without dismiss
  }
};

const loadConnections = async () => {
  if (isLoading.value) {
    return;
  }

  if (!isAdmin.value) {
    return;
  }

  if (!isValidAccountId(accountId.value)) {
    return;
  }

  isLoading.value = true;
  try {
    const response = await wahaConnectionsAPI.getAll();
    connections.value = Array.isArray(response?.data) ? response.data : [];

    const problematic = connections.value.filter(
      connection =>
        connection && PROBLEMATIC_STATUSES.includes(connection.status)
    );

    if (problematic.length > 0 && userDismissedBanner.value) {
      try {
        const dismissed = LocalStorage.get(DISMISS_STORAGE_KEY);
        if (!dismissed) {
          userDismissedBanner.value = false;
        }
      } catch {
        // If localStorage access fails, ignore
      }
    }
  } catch {
    connections.value = [];
  } finally {
    isLoading.value = false;
  }
};

const startPolling = () => {
  if (!isAdmin.value) {
    return;
  }

  if (!shouldPollOnCurrentRoute.value) {
    return;
  }

  if (!isValidAccountId(accountId.value)) {
    return;
  }

  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }

  loadConnections();

  pollingInterval.value = setInterval(() => {
    if (document.visibilityState === 'visible') {
      loadConnections();
    }
  }, POLLING_INTERVAL);
};

const stopPolling = () => {
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
};

const goToConnections = () => {
  if (isValidAccountId(accountId.value)) {
    router.push({
      name: 'waha_connections_list',
      params: { accountId: accountId.value },
    });
  }
};

const dismissBanner = () => {
  userDismissedBanner.value = true;
  try {
    LocalStorage.set(DISMISS_STORAGE_KEY, true);
  } catch {
    // If localStorage write fails (e.g. private mode), just update local state
  }
};

watch(
  accountId,
  (newAccountId, oldAccountId) => {
    const isValidNewId = isValidAccountId(newAccountId);

    if (isValidNewId && newAccountId !== oldAccountId) {
      stopPolling();
      connections.value = [];
      userDismissedBanner.value = false;
      checkDismissedState();
      startPolling();
    } else if (!isValidNewId) {
      stopPolling();
      connections.value = [];
    }
  },
  { immediate: false }
);

watch(
  () => route.path,
  () => {
    stopPolling();
    if (shouldPollOnCurrentRoute.value) {
      startPolling();
    }
  }
);

const handleVisibilityChange = () => {
  if (
    document.visibilityState === 'visible' &&
    shouldPollOnCurrentRoute.value
  ) {
    loadConnections();
  }
};

onMounted(() => {
  checkDismissedState();
  document.addEventListener('visibilitychange', handleVisibilityChange);
  if (shouldPollOnCurrentRoute.value && isValidAccountId(accountId.value)) {
    startPolling();
  }
});

onUnmounted(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange);
  stopPolling();
});
</script>

<template>
  <div v-if="shouldShowBanner" class="waha-connections-banner-wrapper">
    <div
      class="flex items-center h-12 px-4 py-3 text-xs text-white banner dark:text-white woot-banner error"
    >
      <div class="banner-content-wrapper">
        <div class="banner-icon">
          <i class="i-lucide-alert-circle" />
        </div>
        <span class="banner-message">
          {{ bannerMessage }}
          <button
            type="button"
            class="banner-action-button"
            @click="goToConnections"
          >
            {{ t('GENERAL_SETTINGS.WAHA_BANNER.GO_TO_CONNECTIONS') }}
          </button>
        </span>
      </div>

      <div class="actions">
        <button
          type="button"
          class="close-button"
          :aria-label="t('GENERAL_SETTINGS.DISMISS')"
          @click="dismissBanner"
        >
          <i class="i-lucide-circle-x" />
        </button>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.waha-connections-banner-wrapper {
  width: 100%;

  .banner {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;

    &.error {
      @apply bg-red-600 text-white;
      background-color: #dc2626; /* red-600 */
    }

    .banner-content-wrapper {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-wrap: nowrap;
      margin: 0 auto;
      gap: 8px;
    }

    .banner-icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;

      i {
        font-size: 16px;
      }
    }

    .banner-message {
      display: inline-flex;
      align-items: center;
      white-space: nowrap;
      font-size: 12px;
      gap: 8px;
    }

    .banner-action-button {
      @apply ml-2 px-3 py-1 text-xs font-semibold;
      @apply bg-white text-red-600;
      @apply rounded-md;
      @apply hover:bg-red-50;
      @apply transition-colors;
      @apply cursor-pointer;
      border: none;
      white-space: nowrap;
    }

    .actions {
      @apply flex gap-1;
      flex-shrink: 0;
      position: absolute;
      right: 16px;
    }

    .close-button {
      @apply flex items-center justify-center;
      @apply text-white dark:text-white;
      @apply hover:opacity-80;
      @apply transition-opacity;
      background: transparent;
      border: none;
      cursor: pointer;
      padding: 4px;

      i {
        font-size: 16px;
      }
    }
  }
}

@media (max-width: 640px) {
  .waha-connections-banner-wrapper {
    .banner {
      .banner-content-wrapper {
        flex-wrap: wrap;
        gap: 4px;
      }

      .banner-message {
        font-size: 11px;
        flex-wrap: wrap;
        justify-content: center;
        text-align: center;
      }

      .banner-action-button {
        @apply px-2 py-0.5;
        font-size: 11px;
      }
    }
  }
}
</style>
