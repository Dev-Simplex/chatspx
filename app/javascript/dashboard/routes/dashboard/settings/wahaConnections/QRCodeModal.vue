<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';

const props = defineProps({
  connection: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'connected']);
const { t } = useI18n();

const qrCode = ref(null);
const isLoading = ref(true);
const error = ref(null);
const pollingInterval = ref(null);
const connectionStatus = ref(props.connection.status);
const elapsedTime = ref(0);
const timerInterval = ref(null);

const isConnected = computed(() => connectionStatus.value === 'WORKING');
const isFailed = computed(() => connectionStatus.value === 'FAILED');

const formattedTime = computed(() => {
  const minutes = Math.floor(elapsedTime.value / 60);
  const seconds = elapsedTime.value % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
});

const stopPolling = () => {
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
};

const loadQRCode = async () => {
  isLoading.value = true;
  error.value = null;

  // Revogar URL anterior se existir
  if (qrCode.value && qrCode.value.startsWith('blob:')) {
    URL.revokeObjectURL(qrCode.value);
  }

  try {
    const response = await wahaConnectionsAPI.getQRCode(props.connection.id);

    // Response.data é um Blob (imagem PNG binária)
    if (response.data instanceof Blob) {
      qrCode.value = URL.createObjectURL(response.data);
    } else {
      error.value = t('WAHA_CONNECTIONS.QR_MODAL.ERROR');
    }
  } catch (err) {
    error.value = t('WAHA_CONNECTIONS.QR_MODAL.ERROR');
  } finally {
    isLoading.value = false;
  }
};

const checkStatus = async () => {
  try {
    const response = await wahaConnectionsAPI.get(props.connection.id);
    connectionStatus.value = response.data.status;

    if (connectionStatus.value === 'WORKING') {
      stopPolling();
      setTimeout(() => {
        emit('connected');
      }, 2000);
    }
    // FAILED será tratado no template
  } catch {
    // Status check failed, will retry on next poll
  }
};

const startPolling = () => {
  pollingInterval.value = setInterval(() => {
    checkStatus();
  }, 3000);
};

const startTimer = () => {
  timerInterval.value = setInterval(() => {
    elapsedTime.value += 1;
  }, 1000);
};

const stopTimer = () => {
  if (timerInterval.value) {
    clearInterval(timerInterval.value);
    timerInterval.value = null;
  }
};

const handleRetry = () => {
  loadQRCode();
  startPolling();
  elapsedTime.value = 0;
};

const handleRestart = async () => {
  try {
    isLoading.value = true;
    error.value = null;

    // Chamar API de restart
    const restartResponse = await wahaConnectionsAPI.restart(
      props.connection.id
    );

    // Atualizar status imediatamente
    if (restartResponse.data && restartResponse.data.status) {
      connectionStatus.value = restartResponse.data.status;
    }

    // Recarregar QR code
    await loadQRCode();

    // Verificar status novamente após um pequeno delay
    setTimeout(async () => {
      await checkStatus();
    }, 1000);

    // Reiniciar timer
    elapsedTime.value = 0;

    // Continuar polling se não estiver ativo
    if (!pollingInterval.value) {
      startPolling();
    }
  } catch (err) {
    error.value = t('WAHA_CONNECTIONS.QR_MODAL.RESTART_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const handleClose = () => {
  stopPolling();
  stopTimer();
  emit('close');
};

onMounted(() => {
  loadQRCode();
  startPolling();
  startTimer();
});

onUnmounted(() => {
  // Limpar blob URL para liberar memória
  if (qrCode.value && qrCode.value.startsWith('blob:')) {
    URL.revokeObjectURL(qrCode.value);
  }
  stopPolling();
  stopTimer();
});
</script>

<template>
  <Modal show :on-close="handleClose" size="medium">
    <div class="flex flex-col">
      <!-- Header -->
      <div
        class="px-8 py-6 bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-800/20 border-b border-n-weak"
      >
        <div class="flex items-center gap-4">
          <div
            class="size-14 rounded-xl bg-green-600 flex items-center justify-center shadow-lg"
          >
            <div class="i-lucide-qr-code size-7 text-white" />
          </div>
          <div>
            <h2 class="text-2xl font-bold text-n-slate-12">
              {{
                isConnected
                  ? $t('WAHA_CONNECTIONS.QR_MODAL.TITLE_CONNECTED')
                  : $t('WAHA_CONNECTIONS.QR_MODAL.TITLE_SCAN')
              }}
            </h2>
            <p class="text-sm text-n-slate-11 mt-1">
              {{ connection.session_name }}
            </p>
          </div>
        </div>
      </div>

      <!-- Content -->
      <div class="px-8 py-8">
        <!-- Success State -->
        <div v-if="isConnected" class="text-center py-8">
          <div class="relative inline-block mb-6">
            <div
              class="size-24 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center animate-bounce"
            >
              <div class="i-lucide-check-circle size-16 text-green-600" />
            </div>
            <div
              class="absolute -top-2 -right-2 size-8 rounded-full bg-green-500 flex items-center justify-center animate-ping"
            >
              <div class="i-lucide-check size-5 text-white" />
            </div>
          </div>
          <h3 class="text-2xl font-bold text-green-600 mb-2">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.CONNECTED_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-4">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.CONNECTED_DESCRIPTION') }}
          </p>
          <div
            class="inline-flex items-center gap-2 px-4 py-2 bg-green-50 dark:bg-green-900/20 rounded-full text-sm text-green-700 dark:text-green-300"
          >
            <div class="i-lucide-clock size-4" />
            {{
              $t('WAHA_CONNECTIONS.QR_MODAL.ELAPSED_TIME', {
                time: formattedTime,
              })
            }}
          </div>
        </div>

        <!-- Loading State -->
        <div v-else-if="isLoading" class="text-center py-8">
          <div
            class="inline-block animate-spin rounded-full h-16 w-16 border-4 border-green-200 border-t-green-600 mb-4"
          />
          <p class="text-sm text-n-slate-11">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.LOADING') }}
          </p>
        </div>

        <!-- Error State -->
        <div v-else-if="error" class="text-center py-8">
          <div
            class="size-20 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center mx-auto mb-4"
          >
            <div class="i-lucide-x-circle size-12 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-n-slate-12 mb-2">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.ERROR_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-6">{{ error }}</p>
          <Button
            color="blue"
            icon="i-lucide-refresh-cw"
            class="!bg-green-600 hover:!bg-green-700 !text-white"
            @click="handleRetry"
          >
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.RETRY') }}
          </Button>
        </div>

        <!-- Failed State -->
        <div v-else-if="isFailed" class="text-center py-8">
          <div
            class="size-20 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center mx-auto mb-4"
          >
            <div class="i-lucide-x-circle size-12 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-n-slate-12 mb-2">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.FAILED_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-6">
            {{ $t('WAHA_CONNECTIONS.QR_MODAL.FAILED_MESSAGE') }}
          </p>
          <Button
            color="blue"
            icon="i-lucide-refresh-cw"
            class="!bg-green-600 hover:!bg-green-700 !text-white"
            :disabled="isLoading"
            @click="handleRestart"
          >
            {{
              isLoading
                ? $t('WAHA_CONNECTIONS.QR_MODAL.RESTARTING')
                : $t('WAHA_CONNECTIONS.QR_MODAL.RESTART')
            }}
          </Button>
        </div>

        <!-- QR Code Display -->
        <div v-else-if="!isFailed" class="flex flex-col items-center">
          <!-- QR Code Image -->
          <div class="relative mb-6">
            <div
              class="p-6 bg-white rounded-2xl shadow-xl border-4 border-green-500"
            >
              <img
                :src="qrCode"
                alt="QR Code"
                class="w-64 h-64 object-contain"
              />
            </div>
            <!-- Animated Corner Borders -->
            <div
              class="absolute top-2 left-2 w-8 h-8 border-t-4 border-l-4 border-green-600 rounded-tl-lg animate-pulse"
            />
            <div
              class="absolute top-2 right-2 w-8 h-8 border-t-4 border-r-4 border-green-600 rounded-tr-lg animate-pulse"
            />
            <div
              class="absolute bottom-2 left-2 w-8 h-8 border-b-4 border-l-4 border-green-600 rounded-bl-lg animate-pulse"
            />
            <div
              class="absolute bottom-2 right-2 w-8 h-8 border-b-4 border-r-4 border-green-600 rounded-br-lg animate-pulse"
            />
          </div>

          <!-- Instructions -->
          <div class="w-full max-w-md space-y-4 mb-6">
            <h4 class="text-lg font-semibold text-n-slate-12 text-center mb-4">
              {{ $t('WAHA_CONNECTIONS.QR_MODAL.HOW_TO_CONNECT') }}
            </h4>
            <div class="space-y-3">
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
                  <span class="text-sm font-bold text-green-600">1</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  <!-- eslint-disable-next-line vue/no-undef-components -->
                  <i18n-t keypath="WAHA_CONNECTIONS.QR_MODAL.STEP_1" tag="span">
                    <template #whatsapp>
                      <span class="font-semibold text-n-slate-12">{{
                        $t('WAHA_CONNECTIONS.QR_MODAL.STEP_1_WHATSAPP')
                      }}</span>
                    </template>
                  </i18n-t>
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
                  <span class="text-sm font-bold text-green-600">2</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  {{ $t('WAHA_CONNECTIONS.QR_MODAL.STEP_2_PREFIX') }}
                  <span class="font-semibold text-n-slate-12">{{
                    $t('WAHA_CONNECTIONS.QR_MODAL.STEP_2_MENU')
                  }}</span>
                  {{ $t('WAHA_CONNECTIONS.QR_MODAL.STEP_2_OR') }}
                  <span class="font-semibold text-n-slate-12">{{
                    $t('WAHA_CONNECTIONS.QR_MODAL.STEP_2_SETTINGS')
                  }}</span>
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
                  <span class="text-sm font-bold text-green-600">3</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  {{ $t('WAHA_CONNECTIONS.QR_MODAL.STEP_3_PREFIX') }}
                  <span class="font-semibold text-n-slate-12">{{
                    $t('WAHA_CONNECTIONS.QR_MODAL.STEP_3_LINKED_DEVICES')
                  }}</span>
                  {{ $t('WAHA_CONNECTIONS.QR_MODAL.STEP_3_AND_THEN') }}
                  <span class="font-semibold text-n-slate-12">{{
                    $t('WAHA_CONNECTIONS.QR_MODAL.STEP_3_LINK_DEVICE')
                  }}</span>
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
                  <span class="text-sm font-bold text-green-600">4</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  <!-- eslint-disable-next-line vue/no-undef-components -->
                  <i18n-t keypath="WAHA_CONNECTIONS.QR_MODAL.STEP_4" tag="span">
                    <template #thisScreen>
                      <span class="font-semibold text-n-slate-12">{{
                        $t('WAHA_CONNECTIONS.QR_MODAL.STEP_4_THIS_SCREEN')
                      }}</span>
                    </template>
                  </i18n-t>
                </div>
              </div>
            </div>
          </div>

          <!-- Status Info -->
          <div
            class="flex items-center gap-3 px-4 py-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-800"
          >
            <div
              class="i-lucide-loader-circle size-5 text-yellow-600 animate-spin"
            />
            <div class="flex-1">
              <p
                class="text-sm font-medium text-yellow-800 dark:text-yellow-200"
              >
                {{ $t('WAHA_CONNECTIONS.QR_MODAL.WAITING') }}
              </p>
              <p class="text-xs text-yellow-700 dark:text-yellow-300">
                {{
                  $t('WAHA_CONNECTIONS.QR_MODAL.ELAPSED_TIME', {
                    time: formattedTime,
                  })
                }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- Actions -->
      <div
        class="px-8 py-4 bg-n-solid-1 border-t border-n-weak flex gap-3 justify-end"
      >
        <Button
          v-if="!isConnected"
          color="slate"
          size="lg"
          @click="handleClose"
        >
          {{ $t('WAHA_CONNECTIONS.QR_MODAL.CANCEL') }}
        </Button>
        <Button
          v-else
          color="blue"
          size="lg"
          icon="i-lucide-check"
          class="!bg-green-600 hover:!bg-green-700 !text-white"
          @click="handleClose"
        >
          {{ $t('WAHA_CONNECTIONS.QR_MODAL.DONE') }}
        </Button>
      </div>
    </div>
  </Modal>
</template>
