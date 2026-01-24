<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store.js';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
  context: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close', 'select-conversation']);

const { t } = useI18n();
const store = useStore();

const searchQuery = ref('');
const dialogRef = ref(null);

const conversationRecords = useMapGetter(
  'conversationSearch/getConversationRecords'
);
const uiFlags = useMapGetter('conversationSearch/getUIFlags');

const isSearching = computed(() => {
  return uiFlags.value?.conversation?.isFetching || false;
});

const hasResults = computed(() => {
  return conversationRecords.value && conversationRecords.value.length > 0;
});

const showEmptyState = computed(() => {
  return (
    !isSearching.value &&
    searchQuery.value.length > 0 &&
    !hasResults.value
  );
});

// Watch para abrir/fechar o dialog e limpar busca
watch(
  () => props.isOpen,
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

// Função para buscar conversas
const searchConversations = async () => {
  if (!searchQuery.value.trim()) {
    store.dispatch('conversationSearch/clearSearchResults');
    return;
  }

  await store.dispatch('conversationSearch/conversationSearch', {
    q: searchQuery.value.trim(),
    page: 1,
  });
};

// Debounce para evitar muitas buscas
let searchTimeout = null;
const handleSearchInput = () => {
  if (searchTimeout) {
    clearTimeout(searchTimeout);
  }
  searchTimeout = setTimeout(() => {
    searchConversations();
  }, 300);
};

const handleClose = () => {
  searchQuery.value = '';
  store.dispatch('conversationSearch/clearSearchResults');
  emit('close');
};

const handleSelectConversation = conversation => {
  emit('select-conversation', conversation);
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="$t('CONVERSATION.SEARCH_CONVERSATIONS')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="xl"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <!-- Campo de busca -->
      <div class="relative">
        <input
          v-model="searchQuery"
          type="text"
          class="w-full px-3 py-2 text-sm border rounded-lg bg-n-solid-1 border-n-slate-6 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand focus:border-transparent"
          :placeholder="$t('CONVERSATION.SEARCH_CONVERSATIONS')"
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
            v-for="conversation in conversationRecords"
            :key="conversation.id"
            class="p-2 rounded-lg cursor-pointer hover:bg-n-slate-2 transition-colors"
            @click="handleSelectConversation(conversation)"
          >
            <div class="flex items-center gap-3">
              <div class="flex-shrink-0">
                <woot-label
                  class="!bg-n-slate-3 dark:!bg-n-solid-3 !border-n-weak dark:!border-n-strong"
                  :title="`#${conversation.id}`"
                  :show-close="false"
                  small
                />
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <p class="text-sm font-medium text-n-slate-12 truncate">
                    {{
                      conversation.contact?.name ||
                      conversation.contact?.email ||
                      `Conversation #${conversation.id}`
                    }}
                  </p>
                </div>
                <div
                  v-if="conversation.additional_attributes?.mail_subject"
                  class="text-xs text-n-slate-11 truncate"
                >
                  {{ conversation.additional_attributes.mail_subject }}
                </div>
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
        <p class="text-sm text-n-slate-11">
          {{ $t('CONVERSATION.SEARCH_CONVERSATIONS') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>


