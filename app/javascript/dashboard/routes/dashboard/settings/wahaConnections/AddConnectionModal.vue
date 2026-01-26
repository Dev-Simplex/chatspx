<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';

const emit = defineEmits(['close', 'created']);
const { t } = useI18n();

const connectionName = ref('');
const isSubmitting = ref(false);
const error = ref('');

const handleSubmit = async () => {
  error.value = '';
  
  if (!connectionName.value.trim()) {
    error.value = t('WAHA_CONNECTIONS.ADD_MODAL.VALIDATION.CONNECTION_NAME_REQUIRED');
    return;
  }
  
  isSubmitting.value = true;
  
  try {
    const response = await wahaConnectionsAPI.create({
      session_name: connectionName.value.trim(),
      inbox_name: connectionName.value.trim(),
    });
    
    useAlert(t('WAHA_CONNECTIONS.MESSAGES.CREATE_SUCCESS'));
    emit('created', response.data);
  } catch (err) {
    console.error('Error creating WAHA connection:', err);
    console.error('Error response:', err.response?.data);
    
    // Show detailed error message if available
    const errorMessage = err.response?.data?.error || 
                        err.response?.data?.message || 
                        err.message || 
                        t('WAHA_CONNECTIONS.MESSAGES.CREATE_ERROR');
    
    error.value = errorMessage;
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};

const handleClose = () => {
  if (!isSubmitting.value) {
    emit('close');
  }
};
</script>

<template>
  <Modal :show="true" :on-close="handleClose" size="medium">
    <div class="flex flex-col">
      <!-- Header com ícone WhatsApp -->
      <div class="px-8 py-6 bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-800/20 border-b border-n-weak">
        <div class="flex items-center gap-4">
          <div class="size-14 rounded-xl flex items-center justify-center shadow-lg" style="background-color: #25D366;">
            <svg viewBox="0 0 32 32" class="size-7">
              <path fill="white" d="M16 0C7.164 0 0 7.164 0 16c0 2.828 0.738 5.578 2.141 7.984L0 32l8.328-2.094C10.641 31.281 13.289 32 16 32c8.836 0 16-7.164 16-16S24.836 0 16 0zm8.016 22.984c-0.344 0.969-2.031 1.781-2.813 1.891-0.75 0.094-1.703 0.141-2.75-0.172-0.625-0.188-1.422-0.438-2.438-0.859-4.266-1.781-7.047-6.078-7.266-6.359-0.203-0.281-1.703-2.266-1.703-4.328 0-2.063 1.078-3.078 1.469-3.5 0.375-0.406 0.828-0.516 1.109-0.516 0.266 0 0.531 0.016 0.766 0.031 0.25 0.016 0.578-0.094 0.906 0.688 0.344 0.813 1.172 2.859 1.281 3.063 0.109 0.203 0.188 0.453 0.063 0.734-0.125 0.297-0.188 0.484-0.375 0.703-0.188 0.234-0.391 0.516-0.563 0.688-0.188 0.203-0.391 0.422-0.172 0.828 0.219 0.391 0.969 1.594 2.078 2.578 1.422 1.266 2.625 1.672 3.016 1.859 0.391 0.188 0.625 0.156 0.859-0.094 0.234-0.25 1-1.172 1.266-1.578 0.266-0.391 0.547-0.328 0.922-0.188 0.391 0.141 2.453 1.156 2.875 1.375 0.422 0.203 0.703 0.313 0.797 0.484 0.109 0.188 0.109 1.063-0.234 2.031z" />
            </svg>
          </div>
          <div>
            <h2 class="text-2xl font-bold text-n-slate-12">
              Adicionar Conexão WhatsApp
            </h2>
            <p class="text-sm text-n-slate-11 mt-1">
              Crie uma nova conexão WhatsApp para atendimento
            </p>
          </div>
        </div>
      </div>

      <!-- Form -->
      <div class="px-8 py-6">
        <div>
          <label class="block text-sm font-semibold text-n-slate-12 mb-2">
            <div class="flex items-center gap-2">
              <div class="i-lucide-tag size-4" />
              Nome da Conexão
              <span class="text-red-500">*</span>
            </div>
          </label>
          <input
            v-model="connectionName"
            type="text"
            placeholder="ex: Atendimento Principal"
            class="w-full px-4 py-3 text-base border rounded-lg bg-n-solid-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-9 focus:ring-2 focus:ring-green-500 focus:border-transparent transition-all"
            :class="{ 'border-red-500': error }"
            :disabled="isSubmitting"
            @input="error = ''"
            @keyup.enter="handleSubmit"
          />
          <p class="mt-2 text-xs text-n-slate-11">
            <div class="i-lucide-info size-3 inline-block mr-1" />
            Nome que será usado para identificar esta conexão no CHAT - SPX
          </p>
          <p v-if="error" class="mt-2 text-sm text-red-600 flex items-center gap-1">
            <div class="i-lucide-alert-circle size-4" />
            {{ error }}
          </p>
        </div>

        <!-- Info Box -->
        <div class="mt-6 p-4 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800">
          <div class="flex gap-3">
            <div class="i-lucide-lightbulb size-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" />
            <div class="text-sm text-green-900 dark:text-green-200">
              <p class="font-medium mb-1">O que acontece após criar?</p>
              <ul class="space-y-1 text-xs">
                <li class="flex items-start gap-1.5">
                  <div class="i-lucide-check size-3 mt-0.5" />
                  Uma nova conexão será criada
                </li>
                <li class="flex items-start gap-1.5">
                  <div class="i-lucide-check size-3 mt-0.5" />
                  Uma caixa de entrada será vinculada automaticamente
                </li>
                <li class="flex items-start gap-1.5">
                  <div class="i-lucide-check size-3 mt-0.5" />
                  Um QR Code será exibido para você escanear com WhatsApp
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <!-- Actions -->
      <div class="px-8 py-4 bg-n-solid-1 border-t border-n-weak flex gap-3 justify-end">
        <button
          class="px-6 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 bg-n-solid-2 hover:bg-n-solid-3 rounded-lg transition-colors"
          :disabled="isSubmitting"
          @click="handleClose"
        >
          Cancelar
        </button>
        <button
          class="inline-flex items-center gap-2 px-6 py-2 text-sm font-semibold text-white rounded-lg shadow-md hover:shadow-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed min-w-[140px] justify-center"
          style="background-color: #25D366;"
          :disabled="isSubmitting"
          @click="handleSubmit"
        >
          <div v-if="isSubmitting" class="i-lucide-loader-circle size-4 animate-spin" />
          <svg v-else viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="size-4">
            <path d="M12 5v14m-7-7h14" />
          </svg>
          <span>{{ isSubmitting ? 'Criando...' : 'Criar Conexão' }}</span>
        </button>
      </div>
    </div>
  </Modal>
</template>

