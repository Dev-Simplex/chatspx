<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

const props = defineProps({
  // eslint-disable-next-line vue/no-unused-properties
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
const isFocused = ref(false);

const uiFlags = computed(() => store.getters['conversationSearch/getUIFlags']);

const isSearching = computed(
  () => uiFlags.value?.conversation?.isFetching || false
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
const performSearch = useDebounceFn(async query => {
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
      // Ignore non-abort search errors
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
  const existingQuery =
    store.getters['conversationSearch/getConversationSearchQuery'] || '';
  if (existingQuery.trim().length > 0) {
    searchQuery.value = existingQuery;
    hasSearchedOnce.value = true;
  }
});

const handleSearch = event => {
  const query = event.target.value;
  searchQuery.value = query;
  performSearch(query);
};

const handleKeyDown = event => {
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
  <div
    class="sticky top-0 z-10 mb-2.5 bg-[var(--wa-sidebar-bg)] dark:bg-[var(--wa-sidebar-bg-dark)]"
  >
    <div class="flex items-center px-3 py-[7px]">
      <div
        class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 transition-colors duration-150 cursor-text"
        :class="[
          isFocused
            ? 'bg-n-solid-1 dark:bg-[#2a3942] border border-[var(--wa-primary)]'
            : 'bg-n-solid-1 dark:bg-[#202c33] border border-[rgba(11,20,26,0.08)] dark:border-[#2a3942]',
        ]"
        @click="handleContainerClick"
      >
        <div
          class="flex items-center justify-center shrink-0 transition-colors duration-200"
        >
          <span
            v-if="!isSearching"
            class="i-lucide-search size-4"
            :class="
              isFocused
                ? 'text-[var(--wa-primary)]'
                : 'text-[#54656f] dark:text-[#aebac1]'
            "
          />
          <div
            v-else
            class="block size-4 border-2 border-n-brand border-t-transparent rounded-full animate-spin"
          />
        </div>
        <input
          ref="searchInputRef"
          v-model="searchQuery"
          type="text"
          :placeholder="placeholderText"
          class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
          @input="handleSearch"
          @keydown="handleKeyDown"
          @focus="isFocused = true"
          @blur="isFocused = false"
        />
        <button
          v-if="hasSearchQuery && !isSearching"
          type="button"
          class="flex items-center justify-center size-8 -mr-1 rounded-full bg-transparent border-0 cursor-pointer transition-colors duration-200 shrink-0 text-[#54656f] dark:text-[#aebac1] hover:bg-[rgba(84,101,111,0.1)] dark:hover:bg-[rgba(134,150,160,0.15)] focus:outline-none"
          :aria-label="t('GENERAL_SETTINGS.WAHA_BANNER.CLEAR_SEARCH')"
          @click="clearSearch"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
    </div>
  </div>
</template>
