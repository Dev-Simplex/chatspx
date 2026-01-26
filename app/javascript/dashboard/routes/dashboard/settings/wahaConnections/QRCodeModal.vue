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
      error.value = 'Formato de resposta inválido';
      console.error('Resposta não é um Blob:', response.data);
    }
  } catch (err) {
    error.value = t('WAHA_CONNECTIONS.QR_MODAL.ERROR');
    console.error('Erro ao carregar QR Code:', err);
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
  } catch (err) {
    console.error('Error checking status:', err);
  }
};

const startPolling = () => {
  pollingInterval.value = setInterval(() => {
    checkStatus();
  }, 3000);
};

const stopPolling = () => {
  if (pollingInterval.value) {
    clearInterval(pollingInterval.value);
    pollingInterval.value = null;
  }
};

const startTimer = () => {
  timerInterval.value = setInterval(() => {
    elapsedTime.value++;
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
    error.value =
      t('WAHA_CONNECTIONS.QR_MODAL.RESTART_ERROR') ||
      'Erro ao reiniciar conexão. Tente novamente.';
    console.error('Error restarting connection:', err);
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
  <Modal :show="true" :on-close="handleClose" size="medium">
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
              {{ isConnected ? 'Conectado!' : 'Escanear QR Code' }}
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
            Conectado com Sucesso!
          </h3>
          <p class="text-sm text-n-slate-11 mb-4">
            Seu WhatsApp foi vinculado à caixa de entrada
          </p>
          <div
            class="inline-flex items-center gap-2 px-4 py-2 bg-green-50 dark:bg-green-900/20 rounded-full text-sm text-green-700 dark:text-green-300"
          >
            <div class="i-lucide-clock size-4" />
            Tempo decorrido: {{ formattedTime }}
          </div>
        </div>

        <!-- Loading State -->
        <div v-else-if="isLoading" class="text-center py-8">
          <div
            class="inline-block animate-spin rounded-full h-16 w-16 border-4 border-green-200 border-t-green-600 mb-4"
          />
          <p class="text-sm text-n-slate-11">Carregando QR Code...</p>
        </div>

        <!-- Error State -->
        <div v-else-if="error" class="text-center py-8">
          <div
            class="size-20 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center mx-auto mb-4"
          >
            <div class="i-lucide-x-circle size-12 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-n-slate-12 mb-2">
            Erro ao Carregar QR Code
          </h3>
          <p class="text-sm text-n-slate-11 mb-6">{{ error }}</p>
          <Button
            color="blue"
            icon="i-lucide-refresh-cw"
            class="!bg-green-600 hover:!bg-green-700 !text-white"
            @click="handleRetry"
          >
            Tentar Novamente
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
            {{
              t('WAHA_CONNECTIONS.QR_MODAL.FAILED_TITLE') || 'QR Code Expirado'
            }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-6">
            {{
              t('WAHA_CONNECTIONS.QR_MODAL.FAILED_MESSAGE') ||
              'O QR code expirou porque demorou muito para ser escaneado. Clique em "Reiniciar" para gerar um novo QR code.'
            }}
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
                ? t('WAHA_CONNECTIONS.QR_MODAL.RESTARTING') || 'Reiniciando...'
                : t('WAHA_CONNECTIONS.QR_MODAL.RESTART') || 'Reiniciar'
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
              Como Conectar:
            </h4>
            <div class="space-y-3">
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <span class="text-sm font-bold text-green-600">1</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  Abra o
                  <span class="font-semibold text-n-slate-12">WhatsApp</span> no
                  seu celular
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <span class="text-sm font-bold text-green-600">2</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  Toque em
                  <span class="font-semibold text-n-slate-12">Menu (⋮)</span> ou
                  <span class="font-semibold text-n-slate-12">Configurações</span>
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <span class="text-sm font-bold text-green-600">3</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  Toque em
                  <span class="font-semibold text-n-slate-12">Aparelhos conectados</span>
                  e depois em
                  <span class="font-semibold text-n-slate-12">Conectar um aparelho</span>
                </div>
              </div>
              <div class="flex items-start gap-3 p-3 bg-n-solid-1 rounded-lg">
                <div
                  class="size-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0"
                >
                  <span class="text-sm font-bold text-green-600">4</span>
                </div>
                <div class="flex-1 text-sm text-n-slate-11">
                  Aponte seu celular para
                  <span class="font-semibold text-n-slate-12">esta tela</span>
                  para escanear o QR Code
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
                Aguardando conexão...
              </p>
              <p class="text-xs text-yellow-700 dark:text-yellow-300">
                Tempo decorrido: {{ formattedTime }}
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
          Cancelar
        </Button>
        <Button
          v-else
          color="blue"
          size="lg"
          icon="i-lucide-check"
          class="!bg-green-600 hover:!bg-green-700 !text-white"
          @click="handleClose"
        >
          Concluir
        </Button>
      </div>
    </div>
  </Modal>
</template>
