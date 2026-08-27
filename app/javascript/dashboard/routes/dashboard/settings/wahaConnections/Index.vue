<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';
import AddConnectionModal from './AddConnectionModal.vue';
import QRCodeModal from './QRCodeModal.vue';

const { t } = useI18n();

const connections = ref([]);
const isLoading = ref(false);
const showAddModal = ref(false);
const showQRModal = ref(false);
const selectedConnection = ref(null);
const showDeletePopup = ref(false);
const pollingInterval = ref(null);
const lastUpdate = ref(null);
const isRefreshing = ref(false);

const loadConnections = async (silent = false) => {
  if (!silent) {
    isLoading.value = true;
  } else {
    isRefreshing.value = true;
  }

  try {
    const response = await wahaConnectionsAPI.getAll();
    connections.value = response.data || [];
    lastUpdate.value = new Date();
  } catch (error) {
    if (!silent) {
      useAlert(t('WAHA_CONNECTIONS.MESSAGES.API_ERROR'));
    }
    connections.value = [];
  } finally {
    isLoading.value = false;
    isRefreshing.value = false;
  }
};

const startPolling = () => {
  pollingInterval.value = setInterval(() => {
    loadConnections(true);
  }, 5000);
};

const stopPolling = () => {
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
};

const handleRefresh = () => {
  loadConnections(false);
};

const formatDate = dateString => {
  if (!dateString) return '-';
  return new Date(dateString).toLocaleDateString('pt-BR', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
};

const formatPhoneNumber = phone => {
  if (!phone) return null;
  // Remove sufixo @c.us do formato do WhatsApp
  return phone.split('@')[0];
};

const formattedLastUpdate = computed(() => {
  if (!lastUpdate.value) return '';
  return new Date(lastUpdate.value).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
});

const getStatusConfig = status => {
  const configs = {
    WORKING: {
      color:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
      icon: 'i-lucide-check-circle',
      iconColor: 'text-green-600',
      text: t('WAHA_CONNECTIONS.STATUS.WORKING'),
    },
    SCAN_QR_CODE: {
      color:
        'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
      icon: 'i-lucide-qr-code',
      iconColor: 'text-yellow-600',
      text: t('WAHA_CONNECTIONS.STATUS.SCAN_QR_CODE'),
    },
    FAILED: {
      color: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
      icon: 'i-lucide-x-circle',
      iconColor: 'text-red-600',
      text: t('WAHA_CONNECTIONS.STATUS.FAILED'),
    },
    STOPPED: {
      color:
        'bg-n-slate-3 text-n-slate-12 dark:bg-n-slate-3 dark:text-n-slate-12',
      icon: 'i-lucide-circle',
      iconColor: 'text-n-slate-11',
      text: t('WAHA_CONNECTIONS.STATUS.STOPPED'),
    },
    STARTING: {
      color:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
      icon: 'i-lucide-loader-circle',
      iconColor: 'text-green-600',
      text: t('WAHA_CONNECTIONS.STATUS.STARTING'),
    },
  };
  return configs[status] || configs.STOPPED;
};

const handleAddConnection = () => {
  showAddModal.value = true;
};

const handleConnectionCreated = connection => {
  showAddModal.value = false;
  selectedConnection.value = connection;
  showQRModal.value = true;
  loadConnections(true);
};

const handleQRConnected = () => {
  showQRModal.value = false;
  selectedConnection.value = null;
  loadConnections(true);
};

const handleViewQR = connection => {
  selectedConnection.value = connection;
  showQRModal.value = true;
};

const handleConnect = async connection => {
  try {
    await wahaConnectionsAPI.connect(connection.id);
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.CONNECT_SUCCESS'));
    loadConnections(true);
  } catch (error) {
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.CONNECT_ERROR'));
  }
};

const handleDisconnect = async connection => {
  try {
    await wahaConnectionsAPI.disconnect(connection.id);
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.DISCONNECT_SUCCESS'));
    loadConnections(true);
  } catch (error) {
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.DISCONNECT_ERROR'));
  }
};

const handleRestart = async connection => {
  try {
    await wahaConnectionsAPI.restart(connection.id);
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.RESTART_SUCCESS'));
    loadConnections(true);
    // Abrir QR modal automaticamente
    handleViewQR(connection);
  } catch (error) {
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.RESTART_ERROR'));
  }
};

// Levar a CAIXA junto e opcional, e nasce DESMARCADO a cada abertura do modal: `inbox.destroy`
// cascateia conversas e mensagens, sem desfazer. O caminho seguro tem de ser o que acontece
// quando a pessoa so clica em Excluir com pressa.
const apagarCaixa = ref(false);

const openDelete = connection => {
  selectedConnection.value = connection;
  apagarCaixa.value = false;
  showDeletePopup.value = true;
};

const confirmDeletion = async () => {
  const levouCaixa = apagarCaixa.value;
  try {
    await wahaConnectionsAPI.delete(selectedConnection.value.id, {
      deleteInbox: levouCaixa,
    });
    // Chaves literais (e nao uma expressao dentro do `t`) porque o extrator de i18n do repo so
    // enxerga chave estatica: com chave dinamica a string sai como nao usada e some numa limpeza.
    useAlert(
      levouCaixa
        ? t('WAHA_CONNECTIONS.MESSAGES.DELETE_SUCCESS')
        : t('WAHA_CONNECTIONS.MESSAGES.DELETE_SUCCESS_KEPT_INBOX')
    );
    loadConnections(true);
  } catch (error) {
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.DELETE_ERROR'));
  } finally {
    showDeletePopup.value = false;
    selectedConnection.value = null;
    apagarCaixa.value = false;
  }
};

const closeDelete = () => {
  showDeletePopup.value = false;
  selectedConnection.value = null;
};

onMounted(() => {
  loadConnections();
  startPolling();
});

onUnmounted(() => {
  stopPolling();
});
</script>

<template>
  <div class="flex-1 overflow-auto bg-n-solid-1">
    <!-- Header Centralizado -->
    <div class="max-w-7xl mx-auto px-6 py-12">
      <div class="text-center">
        <!-- Logo WhatsApp SVG -->
        <div class="mb-6">
          <div
            class="inline-flex items-center justify-center size-20 rounded-2xl bg-gradient-to-br from-green-400 to-green-600 shadow-lg"
          >
            <svg viewBox="0 0 32 32" class="size-12">
              <path
                fill="white"
                d="M16 0C7.164 0 0 7.164 0 16c0 2.828 0.738 5.578 2.141 7.984L0 32l8.328-2.094C10.641 31.281 13.289 32 16 32c8.836 0 16-7.164 16-16S24.836 0 16 0zm8.016 22.984c-0.344 0.969-2.031 1.781-2.813 1.891-0.75 0.094-1.703 0.141-2.75-0.172-0.625-0.188-1.422-0.438-2.438-0.859-4.266-1.781-7.047-6.078-7.266-6.359-0.203-0.281-1.703-2.266-1.703-4.328 0-2.063 1.078-3.078 1.469-3.5 0.375-0.406 0.828-0.516 1.109-0.516 0.266 0 0.531 0.016 0.766 0.031 0.25 0.016 0.578-0.094 0.906 0.688 0.344 0.813 1.172 2.859 1.281 3.063 0.109 0.203 0.188 0.453 0.063 0.734-0.125 0.297-0.188 0.484-0.375 0.703-0.188 0.234-0.391 0.516-0.563 0.688-0.188 0.203-0.391 0.422-0.172 0.828 0.219 0.391 0.969 1.594 2.078 2.578 1.422 1.266 2.625 1.672 3.016 1.859 0.391 0.188 0.625 0.156 0.859-0.094 0.234-0.25 1-1.172 1.266-1.578 0.266-0.391 0.547-0.328 0.922-0.188 0.391 0.141 2.453 1.156 2.875 1.375 0.422 0.203 0.703 0.313 0.797 0.484 0.109 0.188 0.109 1.063-0.234 2.031z"
              />
            </svg>
          </div>
        </div>

        <!-- Título -->
        <h1 class="text-4xl font-bold text-n-slate-12 mb-3">
          {{ $t('WAHA_CONNECTIONS.TITLE') }}
        </h1>
        <p class="text-lg text-n-slate-11 max-w-2xl mx-auto mb-8">
          {{ $t('WAHA_CONNECTIONS.DESCRIPTION') }}
        </p>

        <!-- Botão Principal GRANDE -->
        <button
          class="inline-flex items-center gap-3 px-10 py-4 text-lg font-bold text-white bg-[#00a884] hover:bg-[#008f72] rounded-xl shadow-xl hover:shadow-2xl transition-all duration-200 transform hover:scale-105"
          @click="handleAddConnection"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-6"
          >
            <path d="M12 5v14m-7-7h14" />
          </svg>
          <span>{{ $t('WAHA_CONNECTIONS.ADD_CONNECTION') }}</span>
        </button>

        <!-- Indicadores -->
        <div class="flex items-center justify-center gap-6 text-sm mt-8">
          <div v-if="!isLoading" class="flex items-center gap-2">
            <div class="relative">
              <div class="size-2 rounded-full bg-green-500" />
              <div
                class="absolute inset-0 size-2 rounded-full bg-green-500 animate-ping"
              />
            </div>
            <span class="text-n-slate-11 font-medium">{{
              $t('WAHA_CONNECTIONS.AUTO_UPDATE')
            }}</span>
          </div>
          <div
            v-if="lastUpdate"
            class="flex items-center gap-2 text-n-slate-11"
          >
            <div class="i-lucide-clock size-4" />
            <span>{{
              $t('WAHA_CONNECTIONS.UPDATED_AT', { time: formattedLastUpdate })
            }}</span>
          </div>
          <button
            class="flex items-center gap-2 text-n-slate-11 hover:text-green-600 transition-colors"
            @click="handleRefresh"
          >
            <div
              class="i-lucide-refresh-cw size-4"
              :class="{ 'animate-spin': isRefreshing }"
            />
            <span>{{ $t('WAHA_CONNECTIONS.REFRESH') }}</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Divisor -->
    <div class="border-t border-n-weak" />

    <!-- Loading State -->
    <div v-if="isLoading" class="max-w-7xl mx-auto px-6 py-20">
      <div class="text-center">
        <div
          class="inline-block animate-spin rounded-full h-16 w-16 border-4 border-green-200 border-t-green-600 mb-6"
        />
        <p class="text-lg text-n-slate-11">
          {{ $t('WAHA_CONNECTIONS.MESSAGES.LOADING') }}
        </p>
      </div>
    </div>

    <!-- Empty State -->
    <div v-else-if="!connections.length" class="max-w-7xl mx-auto px-6 py-20">
      <div class="text-center">
        <div
          class="inline-flex items-center justify-center size-32 rounded-full bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-800/20 mb-6"
        >
          <svg viewBox="0 0 32 32" class="size-16">
            <path
              fill="#25D366"
              d="M16 0C7.164 0 0 7.164 0 16c0 2.828 0.738 5.578 2.141 7.984L0 32l8.328-2.094C10.641 31.281 13.289 32 16 32c8.836 0 16-7.164 16-16S24.836 0 16 0zm8.016 22.984c-0.344 0.969-2.031 1.781-2.813 1.891-0.75 0.094-1.703 0.141-2.75-0.172-0.625-0.188-1.422-0.438-2.438-0.859-4.266-1.781-7.047-6.078-7.266-6.359-0.203-0.281-1.703-2.266-1.703-4.328 0-2.063 1.078-3.078 1.469-3.5 0.375-0.406 0.828-0.516 1.109-0.516 0.266 0 0.531 0.016 0.766 0.031 0.25 0.016 0.578-0.094 0.906 0.688 0.344 0.813 1.172 2.859 1.281 3.063 0.109 0.203 0.188 0.453 0.063 0.734-0.125 0.297-0.188 0.484-0.375 0.703-0.188 0.234-0.391 0.516-0.563 0.688-0.188 0.203-0.391 0.422-0.172 0.828 0.219 0.391 0.969 1.594 2.078 2.578 1.422 1.266 2.625 1.672 3.016 1.859 0.391 0.188 0.625 0.156 0.859-0.094 0.234-0.25 1-1.172 1.266-1.578 0.266-0.391 0.547-0.328 0.922-0.188 0.391 0.141 2.453 1.156 2.875 1.375 0.422 0.203 0.703 0.313 0.797 0.484 0.109 0.188 0.109 1.063-0.234 2.031z"
            />
          </svg>
        </div>
        <h3 class="text-2xl font-bold text-n-slate-12 mb-3">
          {{ $t('WAHA_CONNECTIONS.NO_CONNECTIONS') }}
        </h3>
        <p class="text-base text-n-slate-11 max-w-md mx-auto mb-8">
          {{ $t('WAHA_CONNECTIONS.NO_CONNECTIONS_DESCRIPTION') }}
        </p>
        <button
          class="inline-flex items-center gap-2 px-8 py-3 text-base font-semibold text-white bg-[#00a884] hover:bg-[#008f72] rounded-lg shadow-lg transition-all"
          @click="handleAddConnection"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="size-5"
          >
            <path d="M12 5v14m-7-7h14" />
          </svg>
          <span>{{ $t('WAHA_CONNECTIONS.ADD_FIRST_CONNECTION') }}</span>
        </button>
      </div>
    </div>

    <!-- Grid de Cards -->
    <div v-else class="max-w-7xl mx-auto px-6 py-12">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div
          v-for="connection in connections"
          :key="connection.id"
          class="bg-n-solid-2 rounded-lg border border-n-weak hover:border-green-500 hover:shadow-lg transition-all duration-200"
        >
          <!-- Card Header -->
          <div class="p-6 border-b border-n-weak">
            <div class="flex items-start gap-4 mb-4">
              <!-- Logo WhatsApp -->
              <div class="relative flex-shrink-0">
                <div
                  class="size-12 rounded-lg flex items-center justify-center bg-[#00a884]"
                >
                  <svg viewBox="0 0 32 32" class="size-7">
                    <path
                      fill="white"
                      d="M16 0C7.164 0 0 7.164 0 16c0 2.828 0.738 5.578 2.141 7.984L0 32l8.328-2.094C10.641 31.281 13.289 32 16 32c8.836 0 16-7.164 16-16S24.836 0 16 0zm8.016 22.984c-0.344 0.969-2.031 1.781-2.813 1.891-0.75 0.094-1.703 0.141-2.75-0.172-0.625-0.188-1.422-0.438-2.438-0.859-4.266-1.781-7.047-6.078-7.266-6.359-0.203-0.281-1.703-2.266-1.703-4.328 0-2.063 1.078-3.078 1.469-3.5 0.375-0.406 0.828-0.516 1.109-0.516 0.266 0 0.531 0.016 0.766 0.031 0.25 0.016 0.578-0.094 0.906 0.688 0.344 0.813 1.172 2.859 1.281 3.063 0.109 0.203 0.188 0.453 0.063 0.734-0.125 0.297-0.188 0.484-0.375 0.703-0.188 0.234-0.391 0.516-0.563 0.688-0.188 0.203-0.391 0.422-0.172 0.828 0.219 0.391 0.969 1.594 2.078 2.578 1.422 1.266 2.625 1.672 3.016 1.859 0.391 0.188 0.625 0.156 0.859-0.094 0.234-0.25 1-1.172 1.266-1.578 0.266-0.391 0.547-0.328 0.922-0.188 0.391 0.141 2.453 1.156 2.875 1.375 0.422 0.203 0.703 0.313 0.797 0.484 0.109 0.188 0.109 1.063-0.234 2.031z"
                    />
                  </svg>
                </div>
                <div
                  v-if="connection.status === 'WORKING'"
                  class="absolute -top-1 -right-1 size-3 rounded-full border-2 border-white dark:border-n-solid-2 bg-[#00a884]"
                />
              </div>

              <!-- Info -->
              <div class="flex-1 min-w-0">
                <h3
                  class="text-base font-bold text-n-slate-12 truncate mb-2"
                  :title="connection.session_name"
                >
                  {{ connection.session_name }}
                </h3>
                <span
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full"
                  :class="getStatusConfig(connection.status).color"
                >
                  <div
                    class="size-3"
                    :class="[
                      getStatusConfig(connection.status).icon,
                      connection.status === 'STARTING' ? 'animate-spin' : '',
                    ]"
                  />
                  {{ getStatusConfig(connection.status).text }}
                </span>
              </div>
            </div>

            <!-- Detalhes -->
            <div class="space-y-2">
              <!-- Phone -->
              <div class="flex items-center gap-2 text-sm">
                <div
                  class="size-4"
                  :class="
                    connection.phone_number
                      ? 'i-lucide-phone text-green-600'
                      : 'i-lucide-phone-off text-n-slate-11'
                  "
                />
                <span
                  class="font-medium"
                  :class="
                    connection.phone_number
                      ? 'text-n-slate-12'
                      : 'text-n-slate-11'
                  "
                >
                  {{
                    formatPhoneNumber(connection.phone_number) ||
                    $t('WAHA_CONNECTIONS.NOT_CONNECTED')
                  }}
                </span>
              </div>

              <!-- Inbox -->
              <div class="flex items-center gap-2 text-sm text-n-slate-11">
                <div class="i-lucide-inbox size-4" />
                <span class="truncate">{{ connection.inbox_name || '-' }}</span>
              </div>

              <!-- Data -->
              <div class="flex items-center gap-2 text-sm text-n-slate-11">
                <div class="i-lucide-calendar size-4" />
                <span>{{ formatDate(connection.created_at) }}</span>
              </div>
            </div>
          </div>

          <!-- Card Actions -->
          <div class="p-4 bg-n-solid-1 flex gap-2">
            <button
              v-if="
                connection.status === 'SCAN_QR_CODE' ||
                connection.status === 'STOPPED'
              "
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 bg-n-solid-2 hover:bg-n-solid-3 rounded-lg transition-colors"
              @click="handleViewQR(connection)"
            >
              <div class="i-lucide-qr-code size-4" />
              <span>{{ $t('WAHA_CONNECTIONS.QR_MODAL.TITLE_SCAN') }}</span>
            </button>

            <button
              v-if="connection.status === 'STOPPED'"
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-semibold text-white rounded-lg transition-all bg-[#00a884]"
              @click="handleConnect(connection)"
            >
              <div class="i-lucide-plug size-4" />
              <span>{{ $t('WAHA_CONNECTIONS.ACTIONS.CONNECT') }}</span>
            </button>

            <button
              v-if="connection.status === 'WORKING'"
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium text-orange-700 hover:text-orange-800 bg-orange-50 hover:bg-orange-100 dark:text-orange-300 dark:bg-orange-900/20 dark:hover:bg-orange-900/30 rounded-lg transition-colors"
              @click="handleDisconnect(connection)"
            >
              <div class="i-lucide-unplug size-4" />
              <span>{{ $t('WAHA_CONNECTIONS.ACTIONS.DISCONNECT') }}</span>
            </button>

            <button
              v-if="connection.status === 'FAILED'"
              class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-semibold text-white rounded-lg transition-all bg-[#00a884]"
              @click="handleRestart(connection)"
            >
              <div class="i-lucide-refresh-cw size-4" />
              <span>{{ $t('WAHA_CONNECTIONS.ACTIONS.RESTART') }}</span>
            </button>

            <button
              class="inline-flex items-center justify-center px-3 py-2 text-sm font-medium text-red-700 hover:text-red-800 bg-red-50 hover:bg-red-100 dark:text-red-300 dark:bg-red-900/20 dark:hover:bg-red-900/30 rounded-lg transition-colors"
              @click="openDelete(connection)"
            >
              <div class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modals -->
    <AddConnectionModal
      v-if="showAddModal"
      @close="showAddModal = false"
      @created="handleConnectionCreated"
    />

    <QRCodeModal
      v-if="showQRModal"
      :connection="selectedConnection"
      @close="showQRModal = false"
      @connected="handleQRConnected"
    />

    <woot-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :on-close="closeDelete"
      :on-confirm="confirmDeletion"
      :title="$t('WAHA_CONNECTIONS.MESSAGES.DELETE_TITLE')"
      :message="$t('WAHA_CONNECTIONS.MESSAGES.DELETE_CONFIRM')"
      :confirm-text="$t('WAHA_CONNECTIONS.ACTIONS.DELETE')"
      :reject-text="$t('WAHA_CONNECTIONS.ADD_MODAL.CANCEL')"
    >
      <label class="flex items-start gap-2">
        <input v-model="apagarCaixa" type="checkbox" class="mt-1" />
        <span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WAHA_CONNECTIONS.MESSAGES.DELETE_INBOX_TOO') }}
          </span>
          <span
            class="block text-xs"
            :class="apagarCaixa ? 'text-n-ruby-11' : 'text-n-slate-11'"
          >
            {{
              apagarCaixa
                ? $t('WAHA_CONNECTIONS.MESSAGES.DELETE_INBOX_WARNING')
                : $t('WAHA_CONNECTIONS.MESSAGES.KEEP_INBOX_HINT')
            }}
          </span>
        </span>
      </label>
    </woot-delete-modal>
  </div>
</template>
