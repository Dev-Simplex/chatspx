<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';
import { LocalStorage } from 'shared/helpers/localStorage';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const connections = ref([]);
const pollingInterval = ref(null);
const userDismissedBanner = ref(false);

const PROBLEMATIC_STATUSES = ['STOPPED', 'FAILED', 'SCAN_QR_CODE'];
const POLLING_INTERVAL = 12000; // 12 segundos
const DISMISS_STORAGE_KEY = 'wahaConnectionsBannerDismissed';

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
    hasProblematicConnections.value &&
    !userDismissedBanner.value &&
    accountId.value &&
    !isNaN(accountId.value) &&
    accountId.value > 0
  );
});

const bannerMessage = computed(() => {
  const count = problematicConnections.value.length;
  if (count === 1 && problematicConnections.value[0]) {
    const connection = problematicConnections.value[0];
    const statusText = getStatusText(connection?.status);
    return `Uma conexão WhatsApp está ${statusText.toLowerCase()}.`;
  }
  return `${count} conexões WhatsApp estão com problemas.`;
});

const getStatusText = status => {
  const statusMap = {
    STOPPED: 'desconectada',
    FAILED: 'com falha',
    SCAN_QR_CODE: 'aguardando escanear QR code',
  };
  return statusMap[status] || 'com problema';
};

const loadConnections = async () => {
  // Verificar se accountId é válido antes de fazer a chamada
  if (!accountId.value || isNaN(accountId.value) || accountId.value <= 0) {
    return;
  }

  try {
    const response = await wahaConnectionsAPI.getAll();
    // Garantir que response.data seja um array
    connections.value = Array.isArray(response?.data) ? response.data : [];
    
    // Verificar se há conexões problemáticas após atualizar
    const problematic = connections.value.filter(connection =>
      connection && PROBLEMATIC_STATUSES.includes(connection.status)
    );
    
    // Se houver conexões problemáticas e o banner estava fechado, reabrir
    if (problematic.length > 0 && userDismissedBanner.value) {
      // Verificar se ainda está no localStorage (pode ter sido fechado em outra aba)
      try {
        const dismissed = LocalStorage.get(DISMISS_STORAGE_KEY);
        if (!dismissed) {
          userDismissedBanner.value = false;
        }
      } catch (e) {
        // Se houver erro ao acessar localStorage, ignorar
        console.warn('Erro ao acessar localStorage:', e);
      }
    }
  } catch (error) {
    // Silenciosamente falha - não queremos mostrar erro se a API falhar
    // Apenas log em desenvolvimento
    if (process.env.NODE_ENV === 'development') {
      console.error('Erro ao carregar conexões WAHA:', error);
    }
    connections.value = [];
  }
};

const startPolling = () => {
  // Verificar se accountId é válido antes de iniciar polling
  if (!accountId.value || isNaN(accountId.value) || accountId.value <= 0) {
    return;
  }

  // Limpar qualquer intervalo existente
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
  
  // Carregar imediatamente
  loadConnections();
  
  // Depois fazer polling periódico
  pollingInterval.value = setInterval(() => {
    loadConnections();
  }, POLLING_INTERVAL);
};

const stopPolling = () => {
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
};

const goToConnections = () => {
  if (accountId.value && !isNaN(accountId.value) && accountId.value > 0) {
    try {
      router.push({
        name: 'waha_connections_list',
        params: { accountId: accountId.value },
      });
    } catch (error) {
      // Se houver erro na navegação, apenas log (não quebrar a aplicação)
      console.warn('Erro ao navegar para conexões:', error);
    }
  }
};

const dismissBanner = () => {
  userDismissedBanner.value = true;
  try {
    LocalStorage.set(DISMISS_STORAGE_KEY, true);
  } catch (error) {
    // Se houver erro ao salvar no localStorage (ex: modo privado), apenas atualizar estado local
    console.warn('Erro ao salvar no localStorage:', error);
  }
};

// Verificar se o banner foi fechado anteriormente
const checkDismissedState = () => {
  try {
    const dismissed = LocalStorage.get(DISMISS_STORAGE_KEY);
    if (dismissed) {
      userDismissedBanner.value = true;
    }
  } catch (error) {
    // Se houver erro ao acessar localStorage, apenas continuar sem dismiss
    console.warn('Erro ao verificar localStorage:', error);
  }
};

// Watch para accountId - reiniciar polling quando mudar
watch(
  accountId,
  (newAccountId, oldAccountId) => {
    // Verificar se o novo accountId é válido
    const isValidNewId = newAccountId && !isNaN(newAccountId) && newAccountId > 0;
    const isValidOldId = oldAccountId && !isNaN(oldAccountId) && oldAccountId > 0;

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

onMounted(() => {
  checkDismissedState();
  // Verificar se accountId é válido antes de iniciar
  if (accountId.value && !isNaN(accountId.value) && accountId.value > 0) {
    startPolling();
  }
});

onUnmounted(() => {
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
            Ir para Conexões
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
