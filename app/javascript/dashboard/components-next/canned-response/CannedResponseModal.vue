<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  searchableQuery: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();
const store = useStore();

const cannedResponses = useMapGetter('getCannedResponses');

const searchInputRef = ref(null);
const dialogRef = ref(null);
const listRef = ref(null);
const searchTerm = ref('');
const activeIndex = ref(0);

const filteredResponses = computed(() => {
  const list = cannedResponses.value || [];
  const term = (searchTerm.value || '').trim().toLowerCase();
  if (!term) return list;
  return list.filter(item => {
    const code = (item.short_code || '').toLowerCase();
    const content = (item.content || '').toLowerCase();
    return code.includes(term) || content.includes(term);
  });
});

const fetchCannedResponses = (key = '') => {
  store.dispatch('getCannedResponse', { searchKey: key });
};

const focusSearch = async () => {
  await nextTick();
  searchInputRef.value?.focus();
};

const resetState = () => {
  searchTerm.value = props.searchableQuery || '';
  activeIndex.value = 0;
};

const close = () => emit('close');

const handleSelect = item => {
  if (!item) return;
  emit('select', {
    id: item.id,
    content: item.content,
    shortCode: item.short_code,
    attachments: item.attachments || [],
  });
};

const scrollActiveIntoView = async () => {
  await nextTick();
  const list = listRef.value;
  if (!list) return;
  const el = list.querySelector(`[data-index="${activeIndex.value}"]`);
  if (el && typeof el.scrollIntoView === 'function') {
    el.scrollIntoView({ block: 'nearest' });
  }
};

const onKeyDown = e => {
  if (!props.show) return;
  if (e.key === 'Escape') {
    e.preventDefault();
    close();
    return;
  }
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    if (filteredResponses.value.length === 0) return;
    activeIndex.value =
      (activeIndex.value + 1) % filteredResponses.value.length;
    scrollActiveIntoView();
    return;
  }
  if (e.key === 'ArrowUp') {
    e.preventDefault();
    if (filteredResponses.value.length === 0) return;
    activeIndex.value =
      (activeIndex.value - 1 + filteredResponses.value.length) %
      filteredResponses.value.length;
    scrollActiveIntoView();
    return;
  }
  if (e.key === 'Enter') {
    e.preventDefault();
    const item = filteredResponses.value[activeIndex.value];
    if (item) handleSelect(item);
  }
};

const handleBackdropClick = e => {
  if (e.target === dialogRef.value) close();
};

const previewLines = content => {
  if (!content) return '';
  const stripped = String(content)
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return stripped;
};

watch(
  () => props.show,
  isOpen => {
    if (isOpen) {
      resetState();
      fetchCannedResponses(searchTerm.value || '');
      focusSearch();
    }
  },
  { immediate: true }
);

watch(searchTerm, () => {
  activeIndex.value = 0;
});

watch(
  () => filteredResponses.value.length,
  newLen => {
    if (activeIndex.value >= newLen) activeIndex.value = 0;
  }
);

onMounted(() => {
  if (props.show) {
    resetState();
    fetchCannedResponses(searchTerm.value || '');
    focusSearch();
  }
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        ref="dialogRef"
        role="dialog"
        aria-modal="true"
        aria-labelledby="canned-response-modal-title"
        class="fixed inset-0 z-[1000] flex items-start justify-center px-4 pt-[10vh] pb-8 bg-n-alpha-black1 backdrop-blur-[4px]"
        @click="handleBackdropClick"
        @keydown="onKeyDown"
      >
        <div
          class="w-full max-w-2xl flex flex-col bg-n-solid-1 dark:bg-[#233138] border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] rounded-xl shadow-[0_8px_32px_rgba(11,20,26,0.18)] overflow-hidden max-h-[80vh]"
          @click.stop
        >
          <header
            class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-slate-3 dark:border-n-slate-7"
          >
            <div class="flex items-center gap-2">
              <span class="i-lucide-message-square-quote size-5 text-n-brand" />
              <h2
                id="canned-response-modal-title"
                class="text-base font-medium text-n-slate-12"
              >
                {{ t('CONVERSATION.REPLYBOX.CANNED_MODAL.TITLE') }}
              </h2>
            </div>
            <button
              type="button"
              class="flex items-center justify-center size-8 rounded-md text-n-slate-11 hover:bg-n-slate-3 dark:hover:bg-n-slate-7"
              :title="t('CONVERSATION.REPLYBOX.CANNED_MODAL.HINT')"
              :aria-label="t('GENERAL.CLOSE')"
              @click="close"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </header>

          <div
            class="flex items-center px-3 py-[7px] border-b border-n-slate-3 dark:border-n-slate-7"
          >
            <div
              class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 transition-colors duration-150 cursor-text bg-n-solid-1 dark:bg-[#202c33] border border-[rgba(11,20,26,0.08)] dark:border-[#2a3942]"
            >
              <div
                class="flex items-center justify-center shrink-0 transition-colors duration-200"
              >
                <span
                  class="i-lucide-search size-4 text-[#54656f] dark:text-[#aebac1]"
                  aria-hidden="true"
                />
              </div>
              <input
                ref="searchInputRef"
                v-model="searchTerm"
                type="text"
                autocomplete="off"
                spellcheck="false"
                :placeholder="
                  t('CONVERSATION.REPLYBOX.CANNED_MODAL.SEARCH_PLACEHOLDER')
                "
                :aria-label="
                  t('CONVERSATION.REPLYBOX.CANNED_MODAL.SEARCH_PLACEHOLDER')
                "
                class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
              />
            </div>
          </div>

          <div
            ref="listRef"
            role="listbox"
            :aria-label="t('CONVERSATION.REPLYBOX.CANNED_MODAL.TITLE')"
            class="flex-1 overflow-y-auto px-2 py-2"
          >
            <div
              v-if="filteredResponses.length === 0"
              class="flex flex-col items-center justify-center gap-2 py-12 text-center"
            >
              <span class="i-lucide-search-x size-8 text-n-slate-9" />
              <p class="text-sm text-n-slate-11">
                {{ t('CONVERSATION.REPLYBOX.CANNED_MODAL.NO_RESULTS') }}
              </p>
            </div>
            <ul v-else class="flex flex-col gap-1">
              <li
                v-for="(item, index) in filteredResponses"
                :key="item.id"
                role="option"
                :aria-selected="index === activeIndex"
                :data-index="index"
                class="flex items-center justify-between h-14 gap-3 px-3 rounded-lg cursor-pointer transition-colors"
                :class="{
                  'bg-n-slate-3 dark:bg-n-slate-7': index === activeIndex,
                  'hover:bg-n-slate-2 dark:hover:bg-n-slate-8':
                    index !== activeIndex,
                }"
                @mouseenter="activeIndex = index"
                @click="handleSelect(item)"
              >
                <p
                  class="flex-1 text-sm text-n-slate-12 leading-snug line-clamp-2 whitespace-pre-wrap break-words"
                >
                  {{ previewLines(item.content) }}
                </p>
                <span
                  class="shrink-0 inline-flex items-center px-2 py-0.5 rounded-md bg-n-slate-4 dark:bg-n-slate-8 text-xs font-mono text-n-slate-11"
                >
                  {{ `/${item.short_code}` }}
                </span>
              </li>
            </ul>
          </div>

          <footer
            class="flex items-center justify-end px-5 py-2.5 border-t border-n-slate-3 dark:border-n-slate-7 bg-n-alpha-1 dark:bg-n-alpha-black2"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION.REPLYBOX.CANNED_MODAL.HINT') }}
            </p>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
