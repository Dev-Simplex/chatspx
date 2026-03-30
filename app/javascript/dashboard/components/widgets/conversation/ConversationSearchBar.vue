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
  <div class="sticky top-0 z-10 mb-2.5 bg-n-solid-1">
    <div class="flex items-center px-2 py-1.5">
      <div
        class="search-container flex items-center w-full h-[35px] rounded-lg px-3 gap-2 transition-all duration-200 cursor-text"
        :class="[
          isFocused
            ? 'bg-white dark:bg-[#2a3942]'
            : 'bg-[#f0f2f5] dark:bg-[#202c33]',
        ]"
        @click="handleContainerClick"
      >
        <div class="flex items-center justify-center shrink-0 transition-colors duration-200">
          <fluent-icon
            v-if="!isSearching && !isFocused"
            icon="search"
            size="16"
            class="text-[#54656f] dark:text-[#aebac1]"
          />
          <fluent-icon
            v-else-if="!isSearching && isFocused"
            icon="arrow-left"
            size="16"
            class="text-[#00a884] dark:text-[#00a884]"
          />
          <div
            v-else
            class="block size-4 border-2 border-[#00a884] border-t-transparent rounded-full animate-spin"
          />
        </div>
        <input
          ref="searchInputRef"
          v-model="searchQuery"
          type="text"
          :placeholder="placeholderText"
          class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[13px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#667781] dark:placeholder:text-[#8696a0] placeholder:font-normal caret-[#00a884]"
          @input="handleSearch"
          @keydown="handleKeyDown"
          @focus="isFocused = true"
          @blur="isFocused = false"
        />
        <button
          v-if="hasSearchQuery && !isSearching"
          type="button"
          class="flex items-center justify-center bg-transparent border-0 p-0.5 cursor-pointer transition-colors duration-200 shrink-0 text-[#54656f] dark:text-[#aebac1] hover:text-[#111b21] dark:hover:text-[#e9edef] focus:outline-none"
          :aria-label="t('GENERAL_SETTINGS.WAHA_BANNER.CLEAR_SEARCH')"
          @click="clearSearch"
        >
          <fluent-icon icon="dismiss-circle" size="16" />
        </button>
      </div>
    </div>
  </div>
</template>
