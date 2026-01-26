<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessageContent from 'dashboard/modules/search/components/MessageContent.vue';
import { dynamicTime } from 'shared/helpers/timeHelper';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const searchQuery = ref('');
const dialogRef = ref(null);
const messageRecords = computed(() => 
  store.getters['conversationSearch/getMessageRecords']
);
const uiFlags = computed(() => 
  store.getters['conversationSearch/getUIFlags']
);

const isSearching = computed(() => 
  uiFlags.value?.message?.isFetching || false
);

const hasResults = computed(() => 
  messageRecords.value && messageRecords.value.length > 0
);

const showEmptyState = computed(() => 
  !isSearching.value && 
  searchQuery.value.trim().length > 0 && 
  !hasResults.value
);

// Watch para abrir/fechar o dialog e limpar busca
watch(
  () => props.show,
  newValue => {
    if (newValue && dialogRef.value) {
      dialogRef.value.open();
    } else if (!newValue && dialogRef.value) {
      dialogRef.value.close();
      searchQuery.value = '';
      store.dispatch('conversationSearch/clearSearchResults');
    }
  },
  { immediate: true }
);

// Função para buscar mensagens dentro da conversa
const searchMessages = async () => {
  const trimmedQuery = searchQuery.value.trim();
  if (!trimmedQuery) {
    store.dispatch('conversationSearch/clearSearchResults');
    return;
  }

  if (!props.conversationId) {
    console.error('[ConversationMessageSearch] conversationId não fornecido');
    return;
  }

  // Garantir que conversation_id seja um número
  const conversationId = Number(props.conversationId);
  if (!conversationId || isNaN(conversationId)) {
    console.error('[ConversationMessageSearch] conversationId inválido:', props.conversationId);
    return;
  }

  await store.dispatch('conversationSearch/messageSearchInConversation', {
    q: trimmedQuery,
    conversation_id: conversationId,
    page: 1,
  });
};

// Debounce para evitar muitas buscas
const performSearch = useDebounceFn(searchMessages, 300);

const handleSearchInput = () => {
  performSearch();
};

const handleClose = () => {
  searchQuery.value = '';
  store.dispatch('conversationSearch/clearSearchResults');
  emit('close');
};

const handleMessageClick = async (message) => {
  if (message?.id) {
    const messageId = Number(message.id);
    if (!messageId || isNaN(messageId)) {
      console.error('[ConversationMessageSearch] messageId inválido:', message.id);
      return;
    }
    
    // Emitir o evento primeiro antes de fechar o modal
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
    
    // Dar um pequeno delay para garantir que o evento seja processado antes de fechar
    setTimeout(() => {
      handleClose();
    }, 150);
  }
};

const getName = (message) => {
  return message?.sender?.name || t('SEARCH.BOT_LABEL');
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="$t('SEARCH.SEARCH_IN_CONVERSATION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="lg"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <!-- Campo de busca -->
      <div class="relative">
        <input
          v-model="searchQuery"
          type="text"
          class="w-full px-3 py-2 text-sm border rounded-lg bg-n-solid-1 border-n-slate-6 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand focus:border-transparent"
          :placeholder="$t('SEARCH.SEARCH_IN_CONVERSATION_PLACEHOLDER')"
          autocomplete="off"
          @input="handleSearchInput"
          @keydown.esc="handleClose"
        />
        <div
          v-if="isSearching"
          class="absolute right-3 top-1/2 -translate-y-1/2"
        >
          <Spinner class="text-n-brand" :size="16" />
        </div>
      </div>

      <!-- Lista de resultados -->
      <div
        v-if="hasResults || isSearching || showEmptyState"
        class="flex flex-col max-h-[400px] overflow-y-auto"
      >
        <div v-if="isSearching && !hasResults" class="flex justify-center p-4">
          <Spinner class="text-n-brand" />
        </div>

        <div
          v-else-if="showEmptyState"
          class="flex flex-col items-center justify-center p-8 text-center"
        >
          <p class="text-sm text-n-slate-11">
            {{ $t('SEARCH.EMPTY_STATE_DEFAULT') }}
          </p>
        </div>

        <div v-else-if="hasResults" class="space-y-1">
          <div
            v-for="message in messageRecords"
            :key="message.id"
            class="p-3 rounded-lg cursor-pointer hover:bg-n-slate-2 transition-colors border border-transparent hover:border-n-weak"
            @click="handleMessageClick(message)"
          >
            <div class="flex items-start gap-3">
              <div class="flex-shrink-0 mt-1">
                <div class="w-8 h-8 rounded-full bg-n-slate-3 dark:bg-n-solid-3 flex items-center justify-center">
                  <fluent-icon 
                    icon="chat" 
                    size="14" 
                    class="text-n-slate-11"
                  />
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ getName(message) }}
                  </p>
                  <span class="text-xs text-n-slate-11">
                    {{ dynamicTime(message.created_at) }}
                  </span>
                </div>
                <MessageContent
                  :author="getName(message)"
                  :message="message"
                  :search-term="searchQuery"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Mensagem inicial -->
      <div
        v-else
        class="flex flex-col items-center justify-center p-8 text-center"
      >
        <fluent-icon icon="search" size="24" class="text-n-slate-11 mb-2" />
        <p class="text-sm text-n-slate-11">
          {{ $t('SEARCH.SEARCH_IN_CONVERSATION_PLACEHOLDER') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
