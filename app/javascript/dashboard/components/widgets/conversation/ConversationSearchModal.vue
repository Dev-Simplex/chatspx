<script setup>
/* eslint-disable vue/no-unused-properties, no-unused-vars */
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

const emit = defineEmits(['close', 'selectConversation']);

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
    !isSearching.value && searchQuery.value.length > 0 && !hasResults.value
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
  emit('selectConversation', conversation);
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
      <!-- Campo de busca (WA-fiel, consistente com ConversationSearchBar) -->
      <div
        class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 bg-n-solid-1 dark:bg-[#202c33] border border-transparent focus-within:border-[var(--wa-primary)]"
      >
        <div class="flex items-center justify-center shrink-0">
          <span
            v-if="!isSearching"
            class="i-lucide-search size-4 text-[#54656f] dark:text-[#aebac1]"
          />
          <Spinner v-else class="text-n-brand" :size="16" />
        </div>
        <input
          v-model="searchQuery"
          type="text"
          class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
          :placeholder="$t('CONVERSATION.SEARCH_CONVERSATIONS')"
          autocomplete="off"
          @input="handleSearchInput"
          @keydown.esc="handleClose"
        />
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
