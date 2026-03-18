<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

const props = defineProps({
  context: {
    type: Object,
    default: () => ({}),
  },
  placeholder: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['clear', 'search']);

const { t } = useI18n();
const store = useStore();

const searchQuery = ref('');
const searchInputRef = ref(null);
const hasSearchedOnce = ref(false);

const uiFlags = computed(() => 
  store.getters['conversationSearch/getUIFlags']
);

const isSearching = computed(() => 
  uiFlags.value?.conversation?.isFetching || false
);

const hasSearchQuery = computed(() => searchQuery.value.trim().length > 0);

const placeholderText = computed(() => {
  if (props.placeholder) {
    return props.placeholder;
  }
  const translated = t('CONVERSATION.SEARCH_CONVERSATIONS');
  if (translated && translated !== 'CONVERSATION.SEARCH_CONVERSATIONS') {
    return translated;
  }
  return 'Buscar conversas';
});

// Debounced search function - 500ms delay, minimum 2 characters
const performSearch = useDebounceFn(async (query) => {
  const trimmedQuery = query.trim();
  if (trimmedQuery.length === 0) {
    // Only emit clear if user actually searched before (not on component mount/remount)
    if (hasSearchedOnce.value) {
      emit('clear');
      hasSearchedOnce.value = false;
    }
    return;
  }

  if (trimmedQuery.length < 2) return;

  hasSearchedOnce.value = true;
  emit('search', trimmedQuery);
  try {
    await store.dispatch('conversationSearch/conversationSearch', {
      q: trimmedQuery,
    });
  } catch (error) {
    if (error?.name !== 'AbortError' && error?.code !== 'ERR_CANCELED') {
      console.error('[ConversationSearchBar] Erro ao buscar conversas:', error);
    }
  }
}, 500);

const clearSearch = () => {
  searchQuery.value = '';
  emit('clear');
  if (searchInputRef.value) {
    searchInputRef.value.focus();
  }
};

onMounted(() => {
  // Restore query from Vuex if search was active (e.g. after component remount)
  const existingQuery = store.getters['conversationSearch/getConversationSearchQuery'] || '';
  if (existingQuery.trim().length > 0) {
    searchQuery.value = existingQuery;
    hasSearchedOnce.value = true;
  }
});

const handleSearch = (event) => {
  const query = event.target.value;
  searchQuery.value = query;
  performSearch(query);
};

const handleKeyDown = (event) => {
  if (event.key === 'Escape' && hasSearchQuery.value) {
    clearSearch();
  }
};

const handleContainerClick = () => {
  if (searchInputRef.value) {
    searchInputRef.value.focus();
  }
};
</script>

<template>
  <div class="conversation-search-bar sticky top-0 z-10 bg-n-solid-1">
    <div class="search-input-wrapper">
      <div class="search-input-container" @click="handleContainerClick">
        <div class="search-icon-wrapper-inline">
          <fluent-icon 
            v-if="!isSearching" 
            icon="search" 
            size="16" 
          />
          <div 
            v-else 
            class="loading-spinner"
          />
        </div>
        <input
          ref="searchInputRef"
          v-model="searchQuery"
          type="text"
          :placeholder="placeholderText"
          class="search-input-inline"
          @input="handleSearch"
          @keydown="handleKeyDown"
        />
        <button
          v-if="hasSearchQuery && !isSearching"
          type="button"
          class="search-clear-button-inline"
          @click="clearSearch"
          aria-label="Limpar busca"
        >
          <fluent-icon icon="dismiss-circle" size="16" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.conversation-search-bar {
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  margin-bottom: 10px;
}

.search-input-wrapper {
  padding: 1px 6px;
  display: flex;
  align-items: center;
}

.search-input-container {
  display: flex;
  align-items: center;
  width: 100%;
  min-height: 30px;
  @apply bg-n-slate-2 dark:bg-n-slate-5;
  border-radius: 999px;
  padding: 2px 10px;
  gap: 8px;
  @apply border border-n-weak;
  transition: background-color 0.2s ease, border-color 0.2s ease;
  cursor: default;
  user-select: none;
}

.search-input-container:focus-within {
  @apply bg-n-slate-1 dark:bg-n-slate-4;
  border-color: rgb(45, 196, 111);
}

.search-icon-wrapper-inline {
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-n-slate-10 dark:text-n-slate-11;
  flex-shrink: 0;
}

.search-input-inline {
  flex: 1;
  min-width: 0;
  border: none !important;
  border-top: none !important;
  border-right: none !important;
  border-bottom: none !important;
  border-left: none !important;
  border-width: 0 !important;
  background: transparent !important;
  background-color: transparent !important;
  outline: none !important;
  font-size: 13px;
  line-height: 1.3;
  padding: 0 !important;
  margin: 0 !important;
  @apply text-n-slate-12 dark:text-n-slate-1;
  box-shadow: none !important;
  -webkit-appearance: none;
  -moz-appearance: none;
  appearance: none;
  border-radius: 0 !important;
  width: 100%;
  font-weight: 400;
  cursor: text;
  user-select: text;
}

.search-input-inline:focus,
.search-input-inline:active,
.search-input-inline:hover {
  border: none !important;
  border-width: 0 !important;
  background: transparent !important;
  background-color: transparent !important;
  box-shadow: none !important;
  outline: none !important;
}

.search-input-inline::placeholder {
  opacity: 0.6;
  @apply text-n-slate-10 dark:text-n-slate-11;
  font-weight: 400;
}

.search-clear-button-inline {
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-n-slate-10 dark:text-n-slate-11;
  background: none;
  border: none;
  padding: 1px;
  cursor: pointer;
  transition: color 0.2s;
  flex-shrink: 0;
  min-width: 18px;
  min-height: 18px;
}

.search-clear-button-inline:hover {
  @apply text-n-slate-12 dark:text-n-slate-1;
}

.search-clear-button-inline:focus {
  outline: none;
}

.loading-spinner {
  width: 16px;
  height: 16px;
  @apply border-n-slate-10 dark:border-n-slate-11;
  border-width: 2px;
  border-top-color: transparent;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  display: block;
}

@keyframes spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}
</style>

