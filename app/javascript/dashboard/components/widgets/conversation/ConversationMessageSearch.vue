<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
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
const inputRef = ref(null);
const activeIdx = ref(-1);
const resultsRef = ref(null);

const messageRecords = computed(
  () => store.getters['conversationSearch/getMessageRecords']
);
const uiFlags = computed(() => store.getters['conversationSearch/getUIFlags']);
const isSearching = computed(() => uiFlags.value?.message?.isFetching || false);
const hasResults = computed(
  () => messageRecords.value && messageRecords.value.length > 0
);
const showEmptyState = computed(
  () =>
    !isSearching.value &&
    searchQuery.value.trim().length > 0 &&
    !hasResults.value
);
const resultCount = computed(() => messageRecords.value?.length || 0);

watch(
  () => props.show,
  val => {
    if (val && dialogRef.value) {
      dialogRef.value.open();
      nextTick(() => {
        setTimeout(() => inputRef.value?.focus(), 50);
      });
    } else if (!val && dialogRef.value) {
      dialogRef.value.close();
      searchQuery.value = '';
      activeIdx.value = -1;
      store.dispatch('conversationSearch/clearSearchResults');
    }
  },
  { immediate: true }
);

const searchMessages = async () => {
  const q = searchQuery.value.trim();
  if (!q) {
    store.dispatch('conversationSearch/clearSearchResults');
    return;
  }
  const convId = Number(props.conversationId);
  if (!convId) return;
  activeIdx.value = -1;
  await store.dispatch('conversationSearch/messageSearchInConversation', {
    q,
    conversation_id: convId,
    page: 1,
  });
};

const performSearch = useDebounceFn(searchMessages, 300);

const handleClose = () => {
  searchQuery.value = '';
  activeIdx.value = -1;
  store.dispatch('conversationSearch/clearSearchResults');
  emit('close');
};

const handleMessageClick = msg => {
  if (!msg?.id) return;
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: Number(msg.id) });
  setTimeout(handleClose, 150);
};

const scrollActiveIntoView = () => {
  nextTick(() => {
    const container = resultsRef.value;
    if (!container) return;
    const active = container.querySelector('[data-active="true"]');
    if (active) {
      active.scrollIntoView({ block: 'nearest' });
    }
  });
};

const handleKeydown = e => {
  if (!hasResults.value) return;
  const len = resultCount.value;
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    activeIdx.value = (activeIdx.value + 1) % len;
    scrollActiveIntoView();
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    activeIdx.value = (activeIdx.value - 1 + len) % len;
    scrollActiveIntoView();
  } else if (e.key === 'Enter' && activeIdx.value >= 0) {
    e.preventDefault();
    handleMessageClick(messageRecords.value[activeIdx.value]);
  }
};

const getName = msg => msg?.sender?.name || t('SEARCH.BOT_LABEL');

const getMsgTypeLabel = msg => {
  const type = msg?.message_type ?? 0;
  if (type === 0) return 'in';
  if (type === 1) return 'out';
  return 'sys';
};

const getPreview = msg => {
  const c = msg?.content || '';
  return c.length <= 140 ? c : `${c.substring(0, 140)}...`;
};

const highlightTerm = text => {
  const q = searchQuery.value.trim();
  if (!q || !text) return text;
  const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return text.replace(
    new RegExp(`(${escaped})`, 'gi'),
    '<mark class="bg-n-amber-3 dark:bg-n-amber-5/40 text-n-slate-12 rounded-sm px-px">$1</mark>'
  );
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
    <div class="flex flex-col gap-3 -mt-1">
      <!-- Search bar -->
      <div class="relative">
        <fluent-icon
          icon="search"
          size="16"
          class="absolute left-3 top-[11px] text-n-slate-10 pointer-events-none"
        />
        <input
          ref="inputRef"
          v-model="searchQuery"
          type="text"
          class="w-full !pl-10 pr-14 py-2 text-sm border rounded-lg bg-n-solid-1 border-n-slate-6 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand focus:border-transparent"
          :placeholder="$t('SEARCH.SEARCH_IN_CONVERSATION_PLACEHOLDER')"
          autocomplete="off"
          @input="performSearch"
          @keydown="handleKeydown"
          @keydown.esc="handleClose"
        />
        <div class="absolute right-3 top-[11px]">
          <Spinner v-if="isSearching" class="text-n-brand" :size="16" />
          <span
            v-else-if="hasResults"
            class="text-[11px] font-medium text-n-slate-10 tabular-nums"
          >
            {{ resultCount }}
          </span>
        </div>
      </div>

      <!-- Results list -->
      <div
        v-if="hasResults || isSearching || showEmptyState"
        ref="resultsRef"
        class="flex flex-col max-h-[360px] overflow-y-auto -mx-1 px-1"
      >
        <!-- Loading -->
        <div
          v-if="isSearching && !hasResults"
          class="flex items-center justify-center py-8"
        >
          <Spinner class="text-n-brand" />
        </div>

        <!-- Empty -->
        <div
          v-else-if="showEmptyState"
          class="flex flex-col items-center justify-center py-10 text-center"
        >
          <fluent-icon icon="search" size="28" class="text-n-slate-9 mb-2" />
          <p class="text-sm text-n-slate-11">
            {{ $t('SEARCH.EMPTY_STATE_DEFAULT') }}
          </p>
        </div>

        <!-- Results -->
        <div v-else-if="hasResults" class="flex flex-col gap-0.5">
          <div
            v-for="(message, idx) in messageRecords"
            :key="message.id"
            :data-active="idx === activeIdx"
            class="flex items-start gap-2.5 px-3 py-2 rounded-lg cursor-pointer transition-colors duration-75"
            :class="
              idx === activeIdx
                ? 'bg-n-brand/8 dark:bg-n-brand/12'
                : 'hover:bg-n-slate-2 dark:hover:bg-n-solid-3'
            "
            @click="handleMessageClick(message)"
            @mouseenter="activeIdx = idx"
          >
            <!-- Type badge -->
            <span
              class="mt-1 shrink-0 inline-flex items-center justify-center w-7 h-5 rounded text-[9px] font-bold uppercase tracking-wide"
              :class="{
                'bg-n-blue-3 text-n-blue-11': getMsgTypeLabel(message) === 'in',
                'bg-n-teal-3 text-n-teal-11':
                  getMsgTypeLabel(message) === 'out',
                'bg-n-slate-3 text-n-slate-10':
                  getMsgTypeLabel(message) === 'sys',
              }"
            >
              {{ getMsgTypeLabel(message) }}
            </span>

            <!-- Content -->
            <div class="flex-1 min-w-0">
              <div class="flex items-baseline gap-2 mb-0.5">
                <span class="text-xs font-semibold text-n-slate-12 truncate">
                  {{ getName(message) }}
                </span>
                <span
                  class="text-[10px] text-n-slate-10 whitespace-nowrap shrink-0"
                >
                  {{ dynamicTime(message.created_at) }}
                </span>
              </div>
              <p
                v-dompurify-html="highlightTerm(getPreview(message))"
                class="text-xs text-n-slate-11 leading-relaxed line-clamp-2"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Initial state -->
      <div
        v-else
        class="flex flex-col items-center justify-center py-8 text-center"
      >
        <fluent-icon icon="search" size="28" class="text-n-slate-9 mb-2" />
        <p class="text-sm text-n-slate-11">
          {{ $t('SEARCH.SEARCH_IN_CONVERSATION_PLACEHOLDER') }}
        </p>
      </div>

      <!-- Keyboard hints -->
      <div
        v-if="hasResults"
        class="flex items-center gap-4 pt-2 border-t border-n-weak text-[10px] text-n-slate-10"
      >
        <!-- eslint-disable vue/no-bare-strings-in-template -->
        <span class="flex items-center gap-1">
          <kbd
            class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded bg-n-slate-3 dark:bg-n-solid-3 text-n-slate-11 font-mono text-[9px] leading-none"
          >
            ↑↓
          </kbd>
          {{ $t('SEARCH.NAVIGATE') }}
        </span>
        <span class="flex items-center gap-1">
          <kbd
            class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded bg-n-slate-3 dark:bg-n-solid-3 text-n-slate-11 font-mono text-[9px] leading-none"
          >
            ↵
          </kbd>
          {{ $t('SEARCH.GO_TO') }}
        </span>
        <span class="flex items-center gap-1">
          <kbd
            class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded bg-n-slate-3 dark:bg-n-solid-3 text-n-slate-11 font-mono text-[9px] leading-none"
          >
            esc
          </kbd>
          {{ $t('SEARCH.CLOSE') }}
        </span>
        <!-- eslint-enable vue/no-bare-strings-in-template -->
      </div>
    </div>
  </Dialog>
</template>
